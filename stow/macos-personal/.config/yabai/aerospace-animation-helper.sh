#!/bin/sh

# AeroSpace owns all tiling. yabai runs only to bypass the native macOS Space
# animation when an application or fullscreen window on another Space is
# focused.
/opt/homebrew/bin/yabai -m config layout float
/opt/homebrew/bin/yabai -m config mouse_follows_focus off
/opt/homebrew/bin/yabai -m config focus_follows_mouse off
/opt/homebrew/bin/yabai -m config skip_window_focus_animation on

# Telegram Desktop reuses an AXDialog named "Media viewer" for its photo/video
# overlay. AeroSpace owns its floating placement; keep the animation-only yabai
# helper from trying to manage the same transient window.
/opt/homebrew/bin/yabai -m rule --remove aerospace-telegram-media >/dev/null 2>&1 || true
/opt/homebrew/bin/yabai -m rule --add \
  label=aerospace-telegram-media \
  app='^Telegram$' \
  title='^Media viewer$' \
  role='^AXWindow$' \
  subrole='^AXDialog$' \
  manage=off
