#!/bin/sh
# Launch the `toph` polybar on every connected monitor (kali). Idempotent.
killall -q polybar
while pgrep -x polybar >/dev/null; do sleep 0.2; done
if type xrandr >/dev/null 2>&1; then
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR=$m polybar --reload toph &
  done
else
  polybar --reload toph &
fi
