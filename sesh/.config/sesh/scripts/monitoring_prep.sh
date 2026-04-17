#!/usr/bin/env bash
# Lay out the monitoring session: window 0 = htop, window 1 = `typtel stats`.
# Runs as the session's `startup_command`, so this script itself is executing
# inside window 0's shell -- queued send-keys fire after the script exits.

S="monitoring"
tmux send-keys -t "$S":0 'htop' Enter
tmux new-window -t "$S": -n typtel -c "$HOME"
tmux send-keys -t "$S":typtel 'typtel stats' Enter
tmux select-window -t "$S":0
