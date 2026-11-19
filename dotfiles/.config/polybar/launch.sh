#!/usr/bin/env bash
# One bar per monitor; the tray goes on the primary monitor only.
# The bars run under a small supervisor that starts them again when one exits. Polybar reloads
# itself on every RandR change (screenchange-reload), and if that happens while the screen is
# asleep or being switched (a DisplayPort monitor leaves X when it powers off), it finds no
# monitors and quits ("No monitors found"). Without the supervisor the bar stays gone.
log=${XDG_STATE_HOME:-$HOME/.local/state}/polybar.log
mkdir -p "${log%/*}"   # without it the >> redirect fails and no bar starts, silently
pidfile=${XDG_RUNTIME_DIR:-/tmp}/polybar-launch.$UID.pid

# Stop the previous supervisor first, or it would start the bars we are about to kill again.
if [[ -f $pidfile ]]; then
  old=$(<"$pidfile")
  [[ $old =~ ^[0-9]+$ ]] && kill -TERM -- "-$old" 2>/dev/null
  rm -f "$pidfile"
fi
# A bar can hang while quitting (its i3 module keeps reconnecting to an i3 that is gone,
# e.g. after logging out), so wait at most 2 s and then kill it outright.
pkill -u "$UID" -x polybar
for _ in {1..20}; do pgrep -u "$UID" -x polybar >/dev/null || break; sleep 0.1; done
pkill -KILL -u "$UID" -x polybar 2>/dev/null

[[ ${1:-} == stop ]] && exit 0

# Returns when polybar's monitor list is no longer $1 (a screen plugged in / out, or rearranged),
# so the supervisor starts one bar per monitor again. Follows X's RandR events (xev; else asks X
# every 2 s with xrandr --current, which never probes the outputs: no dGPU wake-ups), and asks
# polybar only when the screens really changed.
watch_monitors() {
  local want=$1 sig new line xevpid=
  screens() { xrandr --current 2>/dev/null | awk '/ connected/'; }
  changed() {
    new=$(screens); [[ $new == "$sig" ]] && return 1
    sig=$new; [[ $(polybar --list-monitors 2>/dev/null) != "$want" ]]
  }
  sig=$(screens)
  if command -v xev >/dev/null; then
    exec {ev}< <(exec xev -root -event randr 2>/dev/null); xevpid=$!
    trap 'kill "$xevpid" 2>/dev/null; exit 0' TERM
    while read -r -u "$ev" line; do
      [[ $line == RRNotify* || $line == RRScreenChangeNotify* ]] || continue
      while read -r -t 1 -u "$ev" _; do :; done   # one plug sends a burst of events
      changed && break
    done
    kill "$xevpid" 2>/dev/null
  else
    while sleep 2; do changed && break; done
  fi
}

supervise() {
  echo "$BASHPID" >"$pidfile"
  trap 'kill $(jobs -p) 2>/dev/null; exit 0' TERM INT HUP
  local monitors primary m bar kind started watcher why delay=1
  while xset q >/dev/null 2>&1; do   # X gone (logged out): stop
    monitors=$(polybar --list-monitors 2>/dev/null)
    if [[ -z $monitors ]]; then sleep 2; continue; fi   # screen asleep / switching: wait for it
    primary=$(awk -F: '/primary/{print $1; exit}' <<<"$monitors")
    [[ -z $primary ]] && primary=$(head -n1 <<<"$monitors" | cut -d: -f1)
    for m in $(cut -d: -f1 <<<"$monitors"); do
      # Easy mode (tux-easymode): the taskbar layout instead.
      kind=main; grep -qsE '^EASY_MODE="?1' "$HOME/.config/tuxcraft/state" && kind=easy
      bar=$kind; [[ $m == "$primary" ]] && bar=$kind-tray
      MONITOR=$m polybar --reload "$bar" >>"$log" 2>&1 &
    done
    started=$SECONDS
    watch_monitors "$monitors" &
    watcher=$!
    # A bar quit, or the monitors changed: start them all again on the monitors there are now.
    wait -n
    if kill -0 "$watcher" 2>/dev/null; then why="a bar exited"; else why="the monitors changed"; fi
    kill $(jobs -p) 2>/dev/null; wait
    echo "polybar-launch: $why; restarting the bars" >>"$log"
    if [[ $why == "a bar exited" ]]; then
      # A bar that dies straight away (broken config) is retried slower and slower, up to 30 s.
      if (( SECONDS - started < 10 )); then delay=$(( delay < 30 ? delay * 2 : 30 )); else delay=1; fi
      sleep "$delay"
    else
      delay=1
    fi
  done
  rm -f "$pidfile"
}

# setsid: own process group, so the next launch can stop the supervisor and its bars together.
export -f supervise watch_monitors; export log pidfile
setsid -f bash -c supervise </dev/null >/dev/null 2>&1
