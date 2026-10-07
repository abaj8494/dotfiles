#!/usr/bin/env bash
# herdr port of ~/.config/sesh/scripts/monitoring_prep.sh.
#
# The sesh original drives tmux directly (`tmux new-window`, `tmux send-keys`),
# so running it from a herdr pane would reach across and rearrange the real
# tmux server. sesh.sh spots that (see translate_startup) and runs this
# instead: same layout, herdr API.
#
# Layout: tab 1 = htop, tab 2 (typtel) = `typtel stats`, focus stays on tab 1.
# Like the tmux version, this executes inside tab 1's shell, so it finishes by
# exec'ing htop over itself.

set -u

. "$(dirname "$0")/../_herdr.sh"

workspace="${HERDR_WORKSPACE_ID:-}"
if [ -z "$workspace" ]; then
  workspace=$(herdr pane current | jq -r '.result.pane.workspace_id // empty')
fi

if [ -n "$workspace" ]; then
  pane=$(herdr tab create --workspace "$workspace" --cwd "$HOME" --label typtel --no-focus |
         jq -r '.result.root_pane.pane_id // empty')
  [ -n "$pane" ] && herdr_run "$pane" "typtel stats"
fi

exec htop
