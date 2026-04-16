#!/usr/bin/env bash
# Pre-create the always-open sesh sessions so they're warm and available
# in `sesh list` / Prefix+T without needing to remember to launch them.
#
# Each entry corresponds to a `[[session]]` in ~/.config/sesh/sesh.toml
# (so startup_command / startup_script / windows are honored).
#
# Usage:
#   ~/.config/sesh/scripts/startup.sh         # idempotent; skips already-running sessions
#
# To run at login, add the following to ~/.config/zsh/.zshrc (outside any
# `if [[ -n $TMUX ]]` guard, since we want it to fire from the login shell):
#
#   if command -v sesh >/dev/null && [ -z "$TMUX" ]; then
#     ~/.config/sesh/scripts/startup.sh >/dev/null 2>&1 &
#   fi

set -u

SESSIONS=(
  monitoring
  remarkable
  flashcards
  configs
  Finances
  jobsync
  uni
)

for name in "${SESSIONS[@]}"; do
  if tmux has-session -t="$name" 2>/dev/null; then
    continue
  fi
  # `sesh connect -d` would be ideal but doesn't exist; instead use sesh's
  # own logic by switching into the session in a detached tmux server,
  # then immediately detach. The session keeps running with all the
  # startup_command / windows wiring.
  ( sesh connect "$name" >/dev/null 2>&1 & )
  # tiny pause so concurrent connects don't race on tmux server creation
  sleep 0.2
done

# Print the resulting session list so the caller can see what's up.
tmux list-sessions 2>/dev/null
