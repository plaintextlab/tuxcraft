#!/usr/bin/env bash
# One bar per monitor; the tray goes on the primary monitor only.
# A bar can hang while quitting (its i3 module keeps reconnecting to an i3 that is gone,
# e.g. after logging out), so wait at most 2 s and then kill it outright.
pkill -u "$UID" -x polybar
for _ in {1..20}; do pgrep -u "$UID" -x polybar >/dev/null || break; sleep 0.1; done
pkill -KILL -u "$UID" -x polybar 2>/dev/null
primary=$(polybar --list-monitors 2>/dev/null | awk -F: '/primary/{print $1; exit}')
[[ -z $primary ]] && primary=$(polybar --list-monitors 2>/dev/null | head -n1 | cut -d: -f1)
for m in $(polybar --list-monitors 2>/dev/null | cut -d: -f1); do
  bar=main; [[ $m == "$primary" ]] && bar=main-tray
  MONITOR=$m polybar --reload "$bar" >>"${XDG_STATE_HOME:-$HOME/.local/state}/polybar.log" 2>&1 &
done
