#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" == "Darwin" ]]; then
    open "x-apple.systempreferences:com.apple.preference.sound"
    exit 0
fi

i3-msg "workspace R2"
pavucontrol &
sleep 0.5
i3-msg '[class="Pavucontrol"] focus'
