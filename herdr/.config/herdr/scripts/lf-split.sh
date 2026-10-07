#!/usr/bin/env bash
# tmux: bind-key l splitw -c "#{pane_current_path}" lf
#       bind-key L splitw -c "#{pane_current_path}" -h lf
#
#   lf-split.sh down|right [command...]     (command defaults to lf)
#
# Three things herdr's own `[[keys.command]] type = "pane"` gets wrong for this:
# it picks the placement itself (a tab, not a split of the current pane), it
# can't take a direction, and the pane outlives the program. So the split goes
# through the socket API instead.
#
# The teardown is the important part. tmux's `splitw lf` makes lf the pane's
# process, so quitting lf kills the pane. herdr has no way to spawn a pane
# *running* a command — `pane.split` takes no command, and layout.apply does
# but it destroys and respawns every existing pane in the tab, which would
# take out whatever is running in them. What does work: split, then type
# "<command>; exit" into the new shell. The shell exits when the program does,
# and herdr closes a pane whose process has gone — same result as tmux.
#
# Bound as type = "shell" (detached): the split is made over the API, so this
# script never needs a pane of its own.

set -u

. "$(cd "$(dirname "$0")" && pwd)/_herdr.sh"

direction="${1:-down}"
shift || true
command_line="${*:-lf}"

case "$direction" in
  down|right) ;;
  *) printf 'lf-split.sh: direction must be down or right\n' >&2; exit 1 ;;
esac

# Custom commands run outside any pane, so fall back to whatever herdr
# considers current; inside a pane, HERDR_PANE_ID is authoritative.
pane="${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}"
if [ -z "$pane" ]; then
  pane=$(herdr pane current | jq -r '.result.pane.pane_id // empty')
fi
[ -n "$pane" ] || { printf 'lf-split.sh: no current pane\n' >&2; exit 1; }

# Split at the *foreground* cwd, matching tmux's #{pane_current_path}.
cwd="${HERDR_ACTIVE_PANE_CWD:-}"
if [ ! -d "${cwd:-}" ]; then
  cwd=$(herdr pane get "$pane" 2>/dev/null | jq -r '.result.pane | (.foreground_cwd // .cwd) // empty')
fi
[ -d "${cwd:-}" ] || cwd="$HOME"

new=$(herdr pane split --pane "$pane" --direction "$direction" --cwd "$cwd" --focus |
      jq -r '.result.pane.pane_id // empty')
[ -n "$new" ] || { printf 'lf-split.sh: split failed\n' >&2; exit 1; }

herdr_wait_prompt "$new"
herdr pane run "$new" "$command_line; exit" >/dev/null
