#!/usr/bin/env bash
# Remember which workspace you came from, so `sesh.sh last` (prefix+C-l, as in
# tmux.conf) can toggle back to it.
#
# tmux gets this for free: `switch-client -l` is built in, and sesh just calls
# it. herdr has no last-workspace action — only previous/next cycling — so the
# history has to be kept here.
#
# Wired to the plugin's [[events]] on = "workspace.focused" hook, which means it
# sees EVERY switch: the sidebar, the picker, prefix+( / ), navigate mode, a
# mouse click. An earlier version only recorded switches made through sesh.sh
# and went stale the moment you used anything else.
#
# State: .current-workspace holds where you are, .last-workspace where you were
# (both by label, which is what `sesh.sh connect` takes).

set -u

STATE_DIR="$HOME/.config/herdr"
CURRENT="$STATE_DIR/.current-workspace"
LAST="$STATE_DIR/.last-workspace"

HERDR_BIN="${HERDR_BIN_PATH:-/opt/homebrew/bin/herdr}"
JQ=/usr/bin/jq

# The event carries a workspace_id; the label is what we need, and it can be
# renamed, so resolve it fresh each time rather than trusting a cached name.
focused=$("$HERDR_BIN" workspace list 2>/dev/null |
  "$JQ" -r '.result.workspaces[]? | select(.focused==true) | .label' | head -1)
[ -n "$focused" ] || exit 0

previous=""
[ -f "$CURRENT" ] && previous=$(<"$CURRENT")

# Focus events also fire for re-focusing the workspace you're already on (tab
# and pane changes bubble up); those must not clobber the history.
if [ -n "$previous" ] && [ "$previous" != "$focused" ]; then
  printf '%s\n' "$previous" >"$LAST"
fi

printf '%s\n' "$focused" >"$CURRENT"
