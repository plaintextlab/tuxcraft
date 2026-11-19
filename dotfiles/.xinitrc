#!/bin/sh
# Started by tux-session (via startx) for the i3 session, or Xfce ("xfce" argument, tux-xfce).
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"
# Hand DISPLAY to D-Bus/systemd so portals, keyring and notifications find the session.
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP 2>/dev/null ||
  dbus-update-activation-environment DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP 2>/dev/null
[ "$1" = xfce ] && exec xfce4-session
exec i3
