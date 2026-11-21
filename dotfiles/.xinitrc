#!/bin/sh
# Started by tux-session (via startx) for the i3 session, Xfce ("xfce" argument, tux-xfce) or
# dwm ("dwm" argument, tux-dwm).
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"
# Hand DISPLAY to D-Bus/systemd so portals, keyring and notifications find the session.
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP 2>/dev/null ||
  dbus-update-activation-environment DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP 2>/dev/null
[ "$1" = xfce ] && exec xfce4-session
# dwm runs nothing at start itself: the session services come from tux-autostart, as in i3.
if [ "$1" = dwm ]; then tux-autostart dwm & exec dwm; fi
exec i3
