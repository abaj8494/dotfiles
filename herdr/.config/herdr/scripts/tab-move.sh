#!/usr/bin/env bash
# tmux: bind H swap-window -t -1 \; select-window -p
#       bind T swap-window -t +1 \; select-window -n
#
# herdr 0.7.5 has no tab-reorder *keybinding* — `move_tab_left`, `swap_tab_*`
# and friends are all rejected as unknown config keys, and the TUI only exposes
# reordering via mouse drag. The socket API does speak `tab.move`, so the
# binding goes through it.
#
#   tab-move.sh left|right
#
# tmux swaps with the neighbour and follows the focus; moving the focused tab
# by one index is the same result, and the tab keeps focus.

set -u

here=$(dirname "$0")
. "$here/_herdr.sh"

case "${1:-}" in
  left|right) direction="$1" ;;
  *) printf 'tab-move.sh: usage: tab-move.sh left|right\n' >&2; exit 1 ;;
esac

tab="${HERDR_ACTIVE_TAB_ID:-${HERDR_TAB_ID:-}}"
if [ -z "$tab" ]; then
  tab=$(herdr pane current | jq -r '.result.pane.tab_id // empty')
fi
[ -n "$tab" ] || { printf 'tab-move.sh: no current tab\n' >&2; exit 1; }

workspace="${tab%%:*}"

# Tab order is the order `tab list` returns for that workspace.
ids=$(herdr tab list | jq -r --arg w "$workspace" '.result.tabs[] | select(.workspace_id==$w) | .tab_id')
count=$(printf '%s\n' "$ids" | grep -c .)
index=$(printf '%s\n' "$ids" | grep -n -x -- "$tab" | cut -d: -f1)
[ -n "$index" ] || { printf 'tab-move.sh: %s not found in %s\n' "$tab" "$workspace" >&2; exit 1; }
index=$((index - 1))   # grep -n is 1-based, insert_index is 0-based

if [ "$direction" = left ]; then
  target=$((index - 1))
else
  target=$((index + 1))
fi
[ "$target" -lt 0 ] && target=0
[ "$target" -ge "$count" ] && target=$((count - 1))
[ "$target" -eq "$index" ] && exit 0

exec "$here/api.py" tab.move "{\"tab_id\": \"$tab\", \"insert_index\": $target}" >/dev/null
