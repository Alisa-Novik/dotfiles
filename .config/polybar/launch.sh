#!/usr/bin/env bash
cd "$(dirname "$(realpath "$0")")"
# Add this script to your wm startup file.


# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# Launch one bar per connected monitor
: > /tmp/polybar.log
polybar -m | cut -d: -f1 | while read -r monitor; do
	MONITOR="$monitor" setsid -f polybar main -c config.ini </dev/null >>/tmp/polybar.log 2>&1
done

sleep 1
xdotool search --class polybar windowraise %@ >/dev/null 2>&1
