#!/usr/bin/env bash
# arrange.sh [toggle] — the bar's tile / float button, for the workspace on the bar's screen.
#   (no argument)  the icon: a grid when every window there floats (click tiles them), else the
#                  float icon (click floats them all, cascaded)
#   toggle         float every window on that workspace, or (all floating already) tile them all
# polybar starts each bar with MONITOR set, so every screen's button acts on its own workspace.
ws=$(i3-msg -t get_workspaces | jq -r --arg m "${MONITOR:-}" '
  [ .[] | select(if $m == "" then .focused else (.visible and .output == $m) end) ][0].name // empty')
[[ -n $ws ]] || { printf '\n'; exit 0; }
tree=$(i3-msg -t get_tree)
# "id floating(yes/no)" for every window on the workspace
rows=$(jq -r --arg ws "$ws" '
  .. | objects | select(.type == "workspace" and .name == $ws)
  | .. | objects | select(.window != null)
  | "\(.id) \(if (.floating // "" | test("on")) then "yes" else "no" end)"' <<<"$tree")

if [[ ${1:-} != toggle ]]; then
  if [[ -n $rows ]] && ! grep -q ' no$' <<<"$rows"; then printf '\n'; else printf '\n'; fi
  exit 0
fi
[[ -n $rows ]] || exit 0
if grep -q ' no$' <<<"$rows"; then
  # Float them all: 60 % x 65 % of the workspace each, cascaded 36 px apart.
  cmds=$(jq -r --arg ws "$ws" '
    .. | objects | select(.type == "workspace" and .name == $ws) as $w
    | ($w.rect) as $r
    | [ $w | .. | objects | select(.window != null) | .id ] | to_entries[]
    | "[con_id=\(.value)] floating enable, resize set \($r.width * 0.6 | floor) px \($r.height * 0.65 | floor) px, move position \($r.x + 40 + .key * 36) px \($r.y + 30 + .key * 36) px"' <<<"$tree")
else
  cmds=$(awk '{ print "[con_id=" $1 "] floating disable" }' <<<"$rows")
fi
i3-msg -q "$(paste -sd';' <<<"$cmds")" >/dev/null 2>&1
exit 0
