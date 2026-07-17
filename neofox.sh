#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" == "Darwin" ]]; then
    if [[ $# -gt 0 ]]; then
        open -na "Firefox" "$1"
    else
        open -na "Firefox"
    fi
    exit 0
fi

if [[ $# -gt 0 ]]; then
    firefox --new-window "$1"
else
    firefox --new-window
fi
