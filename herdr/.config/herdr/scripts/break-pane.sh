#!/usr/bin/env bash
# tmux: bind ! break-pane   (move the current pane into a tab of its own)
#
# `herdr pane move <id> --new-tab` does exactly this; there's just no [keys]
# action for it, so it needs a custom command. Like tmux, refuse when the pane
# is already alone in its tab — herdr would otherwise leave an empty tab behind.

set -u

. "$(cd "$(dirname "$0")" && pwd)/_herdr.sh"

pane="${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}"
if [ -z "$pane" ]; then
  pane=$(herdr pane current | jq -r '.result.pane.pane_id // empty')
fi
[ -n "$pane" ] || { printf 'break-pane.sh: no current pane\n' >&2; exit 1; }

tab=$(herdr pane get "$pane" | jq -r '.result.pane.tab_id // empty')
siblings=$(herdr pane list | jq -r --arg t "$tab" '[.result.panes[] | select(.tab_id==$t)] | length')
[ "${siblings:-1}" -gt 1 ] || { printf "break-pane.sh: can't break a pane that's alone in its tab\n" >&2; exit 1; }

exec herdr pane move "$pane" --new-tab --focus >/dev/null
