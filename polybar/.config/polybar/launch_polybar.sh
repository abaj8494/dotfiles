#!/bin/sh
# Launch the `toph` polybar on every connected monitor (kali). Singleton.
#
# i3 runs this via `exec_always` (so it re-fires on every i3 reload), and
# `screenchange-reload`/manual runs can trigger it too. Without serialisation
# several invocations race past the `killall` teardown before any has spawned,
# then each spawns its own bar → duplicate stacked polybars. An flock guard
# serialises them: invocations queue, each tears down then respawns, so the
# last one wins and exactly one bar per monitor survives.
#
# The spawned polybars get `9>&-` so they DON'T inherit the lock fd — otherwise
# the lock's open-file-description would stay open for polybar's whole lifetime
# and the next launcher would block forever instead of taking its turn.
LOCK="${XDG_RUNTIME_DIR:-/tmp}/polybar-launch.lock"
exec 9>"$LOCK"
flock 9   # block until any in-flight launch finishes, then take our turn

# Tear down existing instances and wait for them to actually exit.
polybar-msg cmd quit >/dev/null 2>&1
killall -q polybar 2>/dev/null
while pgrep -u "$(id -u)" -x polybar >/dev/null; do sleep 0.2; done

if type xrandr >/dev/null 2>&1; then
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR=$m polybar --reload toph >/dev/null 2>&1 9>&- &
  done
else
  polybar --reload toph >/dev/null 2>&1 9>&- &
fi
