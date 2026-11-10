#!/usr/bin/env bash
# Collapsible bar section, like the Windows tray overflow.
#   collapse.sh toggle MOD...   click handler: show/hide MOD... on every bar
#   collapse.sh reset           hook-0 of [module/collapse]: collapsed (bar start)
# The modules start hidden (hidden = true in config.ini). A bar (re)start runs
# hook-0, which clears the state file, so state and bar never disagree for long.
# The chevron itself is format-0/format-1 in config.ini (hook-0 collapsed, hook-1 open).
state=${XDG_RUNTIME_DIR:-/tmp}/tux-polybar-expanded

case $1 in
  reset) rm -f "$state" ;;
  icon)  # older configs: the hook printed the chevron
    if [[ ${2:-} == open ]]; then echo "󰅂"; else rm -f "$state"; echo "󰅁"; fi ;;
  toggle)
    shift
    if [[ -e $state ]]; then rm -f "$state"; act=module_hide; hook=0
    else : >"$state"; act=module_show; hook=1; fi
    for m in "$@"; do polybar-msg action "$m" "$act" >/dev/null 2>&1; done
    polybar-msg action collapse hook "$hook" >/dev/null 2>&1 ;;
esac
