#!/usr/bin/env bash
# Lay out the monitoring session: htop in the left pane, typtel in the right.
# Both run immediately -- they're idempotent monitors.

tmux split-window -h -c "#{pane_current_path}"
tmux send-keys -t :.0 'htop' Enter
tmux send-keys -t :.1 'typtel' Enter
tmux select-pane -t :.0
