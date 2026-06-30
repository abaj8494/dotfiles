#!/bin/sh
# rofi + zoxide directory jumper — pick a frecent dir, open a terminal there.
# Bind to a key in i3/xfwm4 (the WM agent's job), e.g.:  bindsym $mod+z exec ~/.config/rofi/scripts/zoxide-jump.sh
dir=$(zoxide query -l 2>/dev/null | rofi -dmenu -i -p "z jump" -theme-str 'window { width: 40%; }')
[ -n "$dir" ] || exit 0
exec setsid -f alacritty --working-directory "$dir" >/dev/null 2>&1
