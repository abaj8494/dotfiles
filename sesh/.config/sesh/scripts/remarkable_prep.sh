#!/usr/bin/env bash
# Pre-stage the two remarkable targets in split panes WITHOUT executing them.
# Run `make remarkable-sync` first, then `make remarkable` only after it finishes,
# to avoid overwriting local progress. `send-keys` without `Enter` leaves the
# command typed at the prompt, unexecuted.

tmux split-window -h -c "#{pane_current_path}"
tmux send-keys -t :.0 'make remarkable-sync'
tmux send-keys -t :.1 'make remarkable'
tmux select-pane -t :.0
