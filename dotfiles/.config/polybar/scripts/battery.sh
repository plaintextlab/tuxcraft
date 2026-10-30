#!/usr/bin/env bash
# Prints nothing on desktops. Colours come from the theme palette.
bat=$(find /sys/class/power_supply -maxdepth 1 -name 'BAT*' | head -n1)
[[ -z $bat ]] && exit 0
. ~/.config/tuxcraft/colors.sh 2>/dev/null
# Some firmware (HP Omen) fails the ACPI full-charge query, so the kernel omits
# capacity. Derive it from energy_*/charge_* when possible, else stay hidden.
if [[ -r $bat/capacity ]]; then cap=$(<"$bat/capacity")
elif [[ -r $bat/energy_full ]] && (( $(<"$bat/energy_full") > 0 )); then cap=$(( $(<"$bat/energy_now") * 100 / $(<"$bat/energy_full") ))
elif [[ -r $bat/charge_full ]] && (( $(<"$bat/charge_full") > 0 )); then cap=$(( $(<"$bat/charge_now") * 100 / $(<"$bat/charge_full") ))
else exit 0; fi
(( cap > 100 )) && cap=100
st=$(<"$bat/status")
icons=(󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹)
i=$(( cap / 10 )); (( i > 9 )) && i=9
icon=${icons[i]}; [[ $st == Charging ]] && icon=󰂄
col=${green:-#88aa55}; (( cap < 50 )) && col=${yellow:-#ddaa33}; (( cap < 20 )) && col=${red:-#cc4444}
echo "%{F$col}$icon%{F-} $cap%"
