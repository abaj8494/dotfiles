#!/usr/bin/env bash
# Force ibus to US Dvorak at login. Called from the autostart .desktop.
# Re-asserts a few times to beat ibus restoring its last-used (qwerty) engine.
target=xkb:us:dvorak:eng

# Wait until ibus is responsive, then set Dvorak.
for i in $(seq 1 30); do
  ibus engine "$target" 2>/dev/null && break
  sleep 1
done

# ibus may restore its saved engine a moment after startup — re-assert to win the race.
for delay in 2 2 3; do
  sleep "$delay"
  ibus engine "$target" 2>/dev/null
done
