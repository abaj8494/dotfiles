#!/bin/zsh
# daily-init.sh — create today's org-roam daily note at midnight.
#
# Runs at 00:00 via launchd agent com.aayushbajaj.daily-init so today's daily
# exists and is initialised (week transclude, recurring tasks, overdue
# carry-forward, calendar/weather, gcal sweep) WITHOUT the user pressing
# `C-c d d`. If asleep at midnight, launchd fires the missed interval on wake.
#
# Mechanism: drive the live Emacs daemon (it holds all the daily hooks) via
# `(org-roam-dailies--capture (current-time) t)` — the goto path behind
# `C-c d d` — which creates the file from the template and runs
# `org-roam-dailies-find-file-hook` (→ aj/daily-file-open-hook).
#
# IMPORTANT — generate ONLY when the file is absent. Re-running the goto on an
# existing daily would save-buffer and bump the org mtime, which the rmsync
# wake-watch / sync-daily pipeline keys off and could turn into a fire loop
# (see ferrari/CLAUDE.md "Don't fire wake-watch on org-newer-than-pdf").
#
# Shell is zsh because, after writing the org, we invoke ferrari's sync-daily.sh
# for an INSTANT device push. That sub-pipeline needs Full Disk Access; launchd
# only grants FDA to /bin/zsh here, and FDA is inherited down the chain only via
# shebang resolution — so sync-daily.sh is invoked as a path, never `bash …`
# (see ferrari/CLAUDE.md "launchd needs an FDA-granted shell").
set -o pipefail

EMACSCLIENT="/Applications/MacPorts/Emacs.app/Contents/MacOS/bin/emacsclient"
DAILY_DIR="$HOME/lattice/notes/daily"
SYNC_DAILY="$HOME/lattice/2-areas/devices/remarkable/ferrari/scripts/sync-daily.sh"
TODAY="$(date +%Y-%m-%d)"
ORG_FILE="$DAILY_DIR/$TODAY.org"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') — $*"; }

log "daily-init starting for $TODAY"

# Hard timeout so a wedged daemon can't hang the launchd job forever.
if [ -x /opt/homebrew/bin/timeout ]; then
    TIMEOUT=/opt/homebrew/bin/timeout
elif [ -x /opt/local/bin/gtimeout ]; then
    TIMEOUT=/opt/local/bin/gtimeout
else
    TIMEOUT=""
fi

# Locate the daemon socket explicitly. emacsclient's default discovery uses
# $TMPDIR/emacs$UID/server, but $TMPDIR can be overridden. getconf
# DARWIN_USER_TEMP_DIR returns the canonical per-user temp dir the daemon
# parks its socket under, independent of $TMPDIR.
USER_TMP="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)"
SOCK="${USER_TMP%/}/emacs$(id -u)/server"
SOCK_ARG=()
[ -S "$SOCK" ] && SOCK_ARG=(--socket-name="$SOCK")

EC=("$EMACSCLIENT" "${SOCK_ARG[@]}")
[ -n "$TIMEOUT" ] && EC=("$TIMEOUT" 120 "$EMACSCLIENT" "${SOCK_ARG[@]}")

# Probe: is the daemon responsive?
if [ -n "$TIMEOUT" ]; then
    if ! "$TIMEOUT" 5 "$EMACSCLIENT" "${SOCK_ARG[@]}" --eval '(+ 1 1)' >/dev/null 2>&1; then
        log "WARNING: Emacs daemon not responsive within 5s — aborting (will retry next fire)"
        exit 0
    fi
fi


# ── Gotcha guard: only GENERATE when absent (regenerating an existing daily
#    would org-touch and risk a wake-watch fire loop). But still REFRESH the
#    Problems block from problems.org so a re-schedule made after the file was
#    first created lands by morning — idempotently, waking the deploy watch
#    only when the file content actually changed (else restore the mtime).
if [ -f "$ORG_FILE" ]; then
    log "today's daily already exists — refreshing in place (no re-generation)"
    BEFORE="$(cksum < "$ORG_FILE" 2>/dev/null || echo a)"
    STAMP="$(mktemp)"; touch -r "$ORG_FILE" "$STAMP"
    # A pre-existing file is not necessarily a *set-up* file: dailies are
    # stubbed out weeks ahead (title + ID only), so "already exists" was
    # refreshing the Problems block of a file that had no Journal/Recurring/
    # Calendar at all — which is how a `** Problems' block ends up stranded
    # at top level (see `aj/delete-orphan-problems-blocks'). Run the full
    # open hook when the file still needs setup; only the already-built case
    # gets the cheap Problems-only refresh.
    #
    # `find-file-noselect' PROMPTS ("changed on disk; really edit the
    # buffer?") when the daemon holds a stale buffer for this file, and a
    # prompt in a frameless daemon blocks it until a human answers. On
    # 2026-08-22 that wedged Emacs from 00:00:05 to 15:41:20 and every
    # ferrari populate that day logged "Emacs server not responsive". Revert
    # a clean stale buffer first so the prompt has nothing to ask about, and
    # bound the call with $TIMEOUT so this job can never hang all day again.
    "${EC[@]}" --eval "(ignore-errors
        (let ((buf (get-file-buffer \"$ORG_FILE\")))
          (when (and buf
                     (not (buffer-modified-p buf))
                     (not (verify-visited-file-modtime buf)))
            (with-current-buffer buf (revert-buffer t t t))))
        (with-current-buffer (find-file-noselect \"$ORG_FILE\")
          (if (aj/daily-needs-setup-p)
              (aj/daily-file-open-hook)
            (aj/insert-problems-due))
          (when (buffer-modified-p) (save-buffer))))" >/dev/null 2>&1 || true
    AFTER="$(cksum < "$ORG_FILE" 2>/dev/null || echo b)"
    if [ "$BEFORE" = "$AFTER" ]; then
        touch -r "$STAMP" "$ORG_FILE"   # no real change — don't wake the watch
        log "daily unchanged — mtime restored"
    else
        log "daily updated — wake-watch/poll will redeploy"
    fi
    rm -f "$STAMP"
    exit 0
fi

RESULT="$("${EC[@]}" --eval '(condition-case err
    (let ((default-directory (expand-file-name "~/")))
      (save-window-excursion
        (org-roam-dailies--capture (current-time) t)
        (when (buffer-modified-p) (save-buffer))
        (format "OK %s" (buffer-file-name))))
  (error (format "ERR %S" err)))' 2>&1)"

log "create result: $RESULT"

case "$RESULT" in
    *'"OK '*) : ;;  # created — fall through to instant deploy
    *)
        log "ERROR: daily creation failed — skipping instant deploy"
        exit 1
        ;;
esac

# ── Instant deploy ───────────────────────────────────────────────────────
# Push the freshly-written daily to the reMarkable devices NOW instead of
# waiting for the next wake-watch (StartInterval=120) tick. Invoke via shebang
# (path as executable) so TCC's responsible-process inherits this zsh's FDA;
# an explicit `bash "$SYNC_DAILY"` would reset it and EPERM on protected paths.
if [ -x "$SYNC_DAILY" ]; then
    log "invoking sync-daily.sh for instant deploy"
    "$SYNC_DAILY" || log "sync-daily.sh returned non-zero (org still created; wake-watch will retry)"
else
    log "sync-daily.sh not executable at $SYNC_DAILY — skipping instant deploy (wake-watch will pick it up)"
fi

log "daily-init done for $TODAY"
exit 0
