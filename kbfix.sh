#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" == "Darwin" ]]; then
    printf 'Configure input source switching in System Settings > Keyboard > Keyboard Shortcuts > Input Sources.\n'
    exit 0
fi

setxkbmap -option grp:ctrl_space_toggle "us,ru"
