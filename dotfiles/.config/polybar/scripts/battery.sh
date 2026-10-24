#!/usr/bin/env bash
# Prints nothing on desktops. Colours come from the theme palette.
bat=$(find /sys/class/power_supply -maxdepth 1 -name 'BAT*' | head -n1)
[[ -z $bat ]] && exit 0
. ~/.config/tuxcraft/colors.sh 2>/dev/null
cap=$(<"$bat/capacity"); st=$(<"$bat/status")
icons=(󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹)
i=$(( cap / 10 )); (( i > 9 )) && i=9
icon=${icons[i]}; [[ $st == Charging ]] && icon=󰂄
col=${green:-#88aa55}; (( cap < 50 )) && col=${yellow:-#ddaa33}; (( cap < 20 )) && col=${red:-#cc4444}
echo "%{F$col}$icon%{F-} $cap%"
