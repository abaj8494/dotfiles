#!/usr/bin/env bash
# herdr port of ~/.config/sesh/scripts/remarkable_prep.sh.
#
# The sesh original drives tmux directly, so sesh.sh substitutes this one under
# herdr (see translate_startup). Same shape: one tab, two stacked panes, with
# `make remarkable-sync` pre-typed on top and `make remarkable` pre-typed
# below — NEITHER executed. Sync has to finish before remarkable runs, or local
# progress gets overwritten.
#
# `herdr pane send-text` is the exact analogue of tmux send-keys without Enter:
# the text lands in the pty and the shell picks it up, here after this script
# exits.

set -u

. "$(dirname "$0")/../_herdr.sh"

pane="${HERDR_PANE_ID:-}"
if [ -z "$pane" ]; then
  pane=$(herdr pane current | jq -r '.result.pane.pane_id // empty')
fi
[ -n "$pane" ] || exit 0

cwd=$(herdr pane get "$pane" | jq -r '.result.pane | (.foreground_cwd // .cwd) // empty')
[ -d "${cwd:-}" ] || cwd="$PWD"

below=$(herdr pane split --pane "$pane" --direction down --cwd "$cwd" --no-focus |
        jq -r '.result.pane.pane_id // empty')

if [ -n "$below" ]; then
  herdr_wait_prompt "$below"
  herdr pane send-text "$below" 'make remarkable' >/dev/null
fi

# Top pane: this script's own shell. The text queues behind the running script
# and appears at the prompt once it exits, exactly like the tmux version.
herdr pane send-text "$pane" 'make remarkable-sync' >/dev/null
herdr pane focus "$pane" >/dev/null 2>&1 || true
