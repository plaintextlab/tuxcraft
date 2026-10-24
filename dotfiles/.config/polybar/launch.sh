#!/usr/bin/env bash
# One bar per monitor; the tray goes on the primary monitor only.
pkill -x polybar
while pgrep -u "$UID" -x polybar >/dev/null; do sleep 0.1; done
primary=$(polybar --list-monitors 2>/dev/null | awk -F: '/primary/{print $1; exit}')
[[ -z $primary ]] && primary=$(polybar --list-monitors 2>/dev/null | head -n1 | cut -d: -f1)
for m in $(polybar --list-monitors 2>/dev/null | cut -d: -f1); do
  bar=main; [[ $m == "$primary" ]] && bar=main-tray
  MONITOR=$m polybar --reload "$bar" >>"${XDG_STATE_HOME:-$HOME/.local/state}/polybar.log" 2>&1 &
done
