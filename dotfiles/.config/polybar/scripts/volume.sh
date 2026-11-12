#!/usr/bin/env bash
# Volume for the default output; icon and colour say what it is:
#   speaker, normal colour   built-in speakers, awake (volume ramp)
#   speaker, warn (yellow)   built-in speakers, asleep (suspended)
#   headset, normal colour   wired headphones / headset
#   headset, info (blue)     any Bluetooth audio device (headset or speaker)
#   monitor, normal colour   HDMI / DisplayPort
# Colours come from the theme (colors.ini). Muted: grey icon + "muted".
#   volume.sh          print once
#   volume.sh tail     print on every change (polybar tail = true); survives audio restarts
#   volume.sh up|down  volume +/-5 %, never above 100 %
#   volume.sh mute     toggle mute
colors=~/.config/polybar/colors.ini
color() { sed -n "s/^$1 *= *//p" "$colors" 2>/dev/null | head -n1; }

render() {
  local def j
  def=$(pactl get-default-sink 2>/dev/null) || { echo "󰖁"; return; }
  j=$(pactl -f json list sinks 2>/dev/null | jq -c --arg n "$def" 'first(.[] | select(.name == $n))') || j=
  [[ -z $j ]] && { echo "󰖁"; return; }
  local state mute vol api port name
  # \x1f, not tabs: read collapses runs of tabs, so an empty field would shift the rest
  IFS=$'\x1f' read -r state mute vol api port name < <(jq -r '[
      .state, (.mute | tostring),
      ((.volume | to_entries | first.value.value_percent // "0%") | rtrimstr("%")),
      (.properties["device.api"] // ""), (.active_port // ""), .name ] | join("\u001f")' <<<"$j")

  local icon laptop=0 bt=0
  if [[ $api == bluez5 ]]; then icon="󰋋"; bt=1
  elif [[ ${port,,} == *headphone* ]]; then icon="󰋋"
  elif [[ ${name,,} == *hdmi* || ${port,,} == *hdmi* ]]; then icon="󰍹"
  else
    laptop=1
    if   ((vol < 34)); then icon="󰕿"
    elif ((vol < 67)); then icon="󰖀"
    else icon="󰕾"; fi
  fi

  local fg label="$vol%"
  if [[ $mute == true ]]; then fg=$(color disabled); label="muted"; [[ $laptop == 1 ]] && icon="󰝟"
  elif [[ $laptop == 1 && $state == SUSPENDED ]]; then fg=$(color warn)
  elif [[ $bt == 1 ]]; then fg=$(color info)
  else fg=$(color primary); fi
  echo "%{F${fg:-#ffffff}}$icon%{F-} $label"
}

case ${1:-} in
  up)
    v=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -o '[0-9]*%' | head -n1 | tr -d %)
    pactl set-sink-volume @DEFAULT_SINK@ "$(( v + 5 > 100 ? 100 : v + 5 ))%" ;;
  down) pactl set-sink-volume @DEFAULT_SINK@ -5% ;;
  mute) pactl set-sink-mute @DEFAULT_SINK@ toggle ;;
  tail)
    while :; do
      render
      # sink = volume/mute/sleep changes, server = default output changed, card = profile/port
      # (headphones plugged in). Batch bursts of events into one redraw.
      pactl subscribe 2>/dev/null | while read -r line; do
        [[ $line == *" on sink "* || $line == *" on server"* || $line == *" on card "* ]] || continue
        while read -r -t 0.15 _; do :; done
        render
      done
      sleep 1   # audio server went away (restart): reconnect
    done ;;
  *) render ;;
esac
