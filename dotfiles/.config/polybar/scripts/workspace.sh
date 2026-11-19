#!/usr/bin/env bash
# workspace.sh prev|next — scroll over the bar's workspace numbers: go to the workspace left
# (scroll up) or right (scroll down) of the current one on this screen, stopping at the ends.
# (polybar's own enable-scroll misses scroll-up in 3.7, so the i3 module calls this instead.)
cur=$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused) | .name')
[[ -n $cur ]] || exit 0
# This screen's workspaces in bar order (numbers first, by number; then the named ones).
target=$(i3-msg -t get_workspaces | jq -r --arg cur "$cur" --arg dir "${1:-next}" '
  (map(select(.name == $cur))[0].output) as $out
  | [ .[] | select(.output == $out) ] | sort_by(if .num >= 0 then .num else 1e9 end, .name)
  | map(.name) as $ws | ($ws | index($cur)) as $i
  | if $dir == "prev" then (if $i > 0 then $ws[$i - 1] else empty end)
    else (if $i < ($ws | length) - 1 then $ws[$i + 1] else empty end) end')
[[ -n $target ]] && i3-msg -q "workspace \"${target//\"/\\\"}\"" >/dev/null
