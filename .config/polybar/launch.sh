#!/usr/bin/env bash
cd "$(dirname "$(realpath "$0")")"
# Add this script to your wm startup file.


# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# Launch the bar
polybar -q main -c config.ini &
