#!/usr/bin/env bash
# try-st.sh — try st as the terminal straight from this checkout, before tux-update ships it.
#   scripts/try-st.sh          build and install st, make tux-term start it (TERMINAL=st)
#   scripts/try-st.sh --back   back to kitty (st stays installed)
# Run it on the desktop itself (not inside a container): it needs sudo for /usr/local/bin.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
state="$HOME/.config/tuxcraft/state"
setterm() { mkdir -p "${state%/*}"; touch "$state"; sed -i '/^TERMINAL=/d' "$state"; [[ -n $1 ]] && echo "TERMINAL=$1" >>"$state"; return 0; }

if [[ ${1:-} == --back ]]; then setterm ''; echo ":: tux-term starts kitty again"; exit 0; fi

# build needs: harfbuzz (ligatures), imlib2 (sixel images), xrender (see-through); chafa for img
if command -v xbps-install >/dev/null; then
  sudo xbps-install -y libX11-devel libXft-devel freetype-devel fontconfig-devel \
    harfbuzz-devel imlib2-devel libXrender-devel pkg-config chafa
elif command -v apt-get >/dev/null; then
  sudo apt-get install -y libx11-dev libxft-dev libfreetype-dev libfontconfig-dev \
    libharfbuzz-dev libimlib2-dev libxrender-dev pkgconf chafa
elif command -v pacman >/dev/null; then
  sudo pacman -S --needed --noconfirm libx11 libxft freetype2 fontconfig harfbuzz imlib2 libxrender pkgconf chafa
fi

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cp -a "$repo/src/st" "$t/"
make -s -C "$t/st" >/dev/null
sudo make -s -C "$t/st" PREFIX=/usr/local install >/dev/null
# the tux-term that knows st, ahead of the installed one
sudo install -m755 "$repo/bin/tux-term" /usr/local/bin/tux-term
# picom: blur behind st, like kitty
for f in picom.conf dwm.conf; do
  [[ -f $HOME/.config/picom/$f ]] && grep -q st-256color "$HOME/.config/picom/$f" ||
    sed -i "s/class_g = 'kitty' || class_g = 'Alacritty'/class_g = 'kitty' || class_g = 'st-256color' || class_g = 'Alacritty'/" "$HOME/.config/picom/$f" 2>/dev/null || true
done
# the theme's terminal font for st (tux-theme writes this line itself once updated)
. "$state" 2>/dev/null || true
if [[ -f $HOME/.Xresources ]] && ! grep -q '^st\.font:' "$HOME/.Xresources"; then
  echo "st.font: ${TERM_FONT:-Iosevka Nerd Font}:size=${TERM_FONT_SIZE:-13}:antialias=true:autohint=true" >>"$HOME/.Xresources"
fi
[[ -n ${DISPLAY:-} ]] && xrdb -merge "$HOME/.Xresources" 2>/dev/null || true
setterm st
echo ":: st $(st -v 2>&1 | awk '{print $2}') installed; Super+Enter now opens st."
echo "   Back to kitty: $0 --back"
