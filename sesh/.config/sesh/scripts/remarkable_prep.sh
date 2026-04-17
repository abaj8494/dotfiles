#!/usr/bin/env bash
# Lay out the remarkable session in a single window with two horizontal panes
# (top/bottom). Top pane: `make remarkable-sync` pre-typed; bottom: `make
# remarkable` pre-typed. NEITHER executed -- run sync first, then remarkable
# only after it finishes, to avoid overwriting local progress.
# Runs as the session's `startup_command`, so the script is executing inside
# pane 0 of window 0; queued send-keys land after the script exits.

S="remarkable"
tmux send-keys -t "$S":0.0 'make remarkable-sync'
tmux split-window -v -t "$S":0 -c "#{pane_current_path}"
tmux send-keys -t "$S":0.1 'make remarkable'
tmux select-pane -t "$S":0.0
