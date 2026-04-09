#!/usr/bin/env zsh
# claude-rescue launcher entry point

# Only auto-launch on tty1
[[ "$(tty)" == "/dev/tty1" ]] || return

# If the rescue launcher exists, start it; otherwise drop to shell
if [[ -x /usr/local/bin/rescue ]]; then
    /usr/local/bin/rescue
fi
