# Shared helpers for the herdr scripts. Sourced, not executed.

# Scripts launched from [[keys.command]] or a popup inherit a stripped PATH
# (same gotcha as tmux `display-popup -E`), so spell out a full one.
PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

# `herdr pane run` is send-keys, not exec: it types into the pane's interactive
# shell. Type too early — before zsh has started reading the pty — and the
# keystrokes vanish. A rendered prompt is proof the shell is listening.
#
# `pane wait-output` blocks until one appears. Its pane id is a leading
# POSITIONAL argument — `--pane <id>` is rejected with "unknown option", which
# is what made this look broken at first. Falls back to polling if the
# subcommand ever changes shape again.
herdr_wait_prompt() {
  local pane="$1" tries="${2:-25}" out
  herdr pane wait-output "$pane" --match '❯' --timeout 5000 >/dev/null 2>&1 && return 0

  while [ "$tries" -gt 0 ]; do
    out=$(herdr pane read "$pane" 2>/dev/null)
    case "$out" in
      *'❯'*) return 0 ;;                      # p10k prompt
    esac
    [ -n "${out//[[:space:]]/}" ] && return 0  # some other prompt rendered
    sleep 0.2
    tries=$((tries - 1))
  done
  return 1
}

# Type a command into a pane once its shell is ready.
herdr_run() {
  herdr_wait_prompt "$1"
  herdr pane run "$1" "$2" >/dev/null 2>&1
}

# Run a command detached, so it outlives the popup that started it.
#
# herdr SIGKILLs a popup's whole process group the moment the popup's
# foreground process exits, and macOS ships no setsid(1). A plain
# `nohup cmd &` therefore loses a race it looks like it should win: bash forks,
# the parent reaches `exit` and the popup tears down before the child is even
# scheduled to open its log — the observed symptom was a detached connect that
# left no log file at all and never focused anything.
#
# So the child puts itself in a new session and hands back a "done" the caller
# can block on (~25ms, one python start). By the time the popup dies the child
# is in its own session and unreachable by the group kill.
HERDR_DETACH_LOG="${HERDR_DETACH_LOG:-$HOME/.config/herdr/.detached.log}"
export HERDR_DETACH_LOG

# Double-fork, because a single fork is not enough in either direction:
#   - the grandchild must not be a process-group leader when it calls setsid(),
#     or setsid() fails EPERM. Under `set -m` bash puts a background job in its
#     own group, which makes the direct child a leader — so fork once more.
#   - the caller must not exit before setsid() has happened, or the group kill
#     still catches it. The handshake is the inherited stdout pipe: command
#     substitution blocks until every copy is closed, and the grandchild only
#     closes its copy (by dup2'ing the log over fd 1) *after* it has detached.
# Hence no FIFO — a FIFO read here is interrupted by the SIGCHLD from the
# first fork's parent exiting, which is what made the first attempt hang.
herdr_detach() {
  local _handshake
  _handshake=$(/usr/bin/python3 -c '
import os, sys
argv = sys.argv[1:]
try:
    if os.fork() > 0:
        os._exit(0)          # skips the except/finally; grandchild is not a leader
    os.setsid()
    fd = os.open(os.environ["HERDR_DETACH_LOG"],
                 os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.dup2(fd, 1)           # closes the handshake pipe: caller may now exit
    os.dup2(fd, 2)
    if fd > 2:
        os.close(fd)
except Exception:
    os.close(1)              # never leave the caller blocked on the pipe
    raise
os.execv(argv[0], argv)
' "$@" 2>/dev/null) || return 1
}
