# shellcheck shell=bash
# Fallbacks for tools a distro does not package (mostly Debian stable).
# Each installs a static upstream release into /usr/local, only if the tool is missing.

_tmpdir() { mktemp -d /tmp/tuxcraft.XXXXXX; }
_is_x86_64() { [[ $(uname -m) == x86_64 ]]; }

ensure_yazi() {
  command -v yazi >/dev/null && return 0; _is_x86_64 || return 0
  local t; t=$(_tmpdir)
  if fetch https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-gnu.zip "$t/y.zip" &&
     (cd "$t" && unzip -q y.zip); then
    install -m755 "$t"/yazi-*/yazi "$t"/yazi-*/ya /usr/local/bin/ && ok "yazi installed from upstream release"
  else warn "Could not install yazi"; fi
  rm -rf "$t"
}

ensure_starship() {
  command -v starship >/dev/null && return 0; _is_x86_64 || return 0
  local t; t=$(_tmpdir)
  if fetch https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-musl.tar.gz "$t/s.tgz"; then
    tar -xzf "$t/s.tgz" -C "$t" && install -m755 "$t/starship" /usr/local/bin/ && ok "starship installed from upstream release"
  else warn "Could not install starship"; fi
  rm -rf "$t"
}

ensure_bluetui() {
  command -v bluetui >/dev/null && return 0; _is_x86_64 || return 0
  fetch https://github.com/pythops/bluetui/releases/latest/download/bluetui-x86_64-linux-musl /usr/local/bin/bluetui &&
    chmod 755 /usr/local/bin/bluetui && ok "bluetui installed from upstream release" || warn "Could not install bluetui"
}

ensure_lazygit() {
  command -v lazygit >/dev/null && return 0; _is_x86_64 || return 0
  local t tag v u; t=$(_tmpdir)
  tag=$(gh_latest_tag jesseduffield/lazygit); v=${tag#v}
  for u in "lazygit_${v}_Linux_x86_64.tar.gz" "lazygit_${v}_linux_x86_64.tar.gz"; do
    fetch "https://github.com/jesseduffield/lazygit/releases/download/$tag/$u" "$t/l.tgz" && break
  done
  if [[ -s $t/l.tgz ]] && tar -xzf "$t/l.tgz" -C "$t" lazygit; then
    install -m755 "$t/lazygit" /usr/local/bin/ && ok "lazygit installed from upstream release"
  else warn "Could not install lazygit"; fi
  rm -rf "$t"
}

# adw-gtk3: makes GTK3 apps look like libadwaita/GTK4 apps, so one palette themes both.
ensure_adw_gtk3() {
  [[ -d /usr/share/themes/adw-gtk3-dark ]] && return 0
  local t tag; t=$(_tmpdir)
  tag=$(gh_latest_tag lassekongo83/adw-gtk3)
  if fetch "https://github.com/lassekongo83/adw-gtk3/releases/download/$tag/adw-gtk3$tag.tar.xz" "$t/a.txz"; then
    tar -xJf "$t/a.txz" -C /usr/share/themes && ok "adw-gtk3 installed from upstream release"
  else warn "Could not install adw-gtk3; GTK3 apps fall back to Adwaita"; fi
  rm -rf "$t"
}

ensure_papirus_folders() {
  command -v papirus-folders >/dev/null && return 0
  fetch https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/master/papirus-folders /usr/local/bin/papirus-folders &&
    chmod 755 /usr/local/bin/papirus-folders || warn "Could not install papirus-folders"
}

# Debian ships fd and bat under other names.
ensure_debian_shims() {
  [[ $DISTRO == debian ]] || return 0
  command -v fd  >/dev/null || { command -v fdfind >/dev/null && ln -sf "$(command -v fdfind)" /usr/local/bin/fd; }
  command -v bat >/dev/null || { command -v batcat >/dev/null && ln -sf "$(command -v batcat)" /usr/local/bin/bat; }
}

ensure_paru() {
  [[ $DISTRO == arch ]] || return 0
  command -v paru >/dev/null && return 0
  info "Building paru (AUR helper) as $TUX_USER"
  local t; t=$(_tmpdir); chown "$TUX_USER" "$t"
  if as_user git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$t/paru-bin" >>"$TUX_LOG" 2>&1 &&
     as_user sh -c "cd '$t/paru-bin' && makepkg --noconfirm" >>"$TUX_LOG" 2>&1; then
    run pacman -U --noconfirm "$t"/paru-bin/paru-bin-*.pkg.tar.* && ok "paru installed"
  else warn "paru build failed (see $TUX_LOG)"; fi
  rm -rf "$t"
}

# X11 clipboard history: fallback to Flathub when the distro package (Void: CopyQ) is missing.
ensure_clipboard() {
  [[ $TUX_SESSION == i3 ]] || return 0
  command -v copyq >/dev/null && return 0
  command -v flatpak >/dev/null || pkg_install flatpak
  run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo &&
    run flatpak install -y --noninteractive flathub com.github.hluk.copyq || warn "CopyQ unavailable; clipboard history disabled"
}

extras_stage() {
  step "Filling gaps with upstream releases where needed"
  ensure_debian_shims
  ensure_yazi
  ensure_starship
  ensure_lazygit
  [[ ${HAS_BT:-0} == 1 ]] || has_word "$TUX_BUNDLES" bluetooth && ensure_bluetui
  ensure_adw_gtk3
  ensure_papirus_folders
  has_word "$TUX_BUNDLES" aur && ensure_paru
  has_word "$TUX_EXCLUDE" copyq || ensure_clipboard
  if has_word "$TUX_BUNDLES" flatpak && command -v flatpak >/dev/null; then
    run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    # Let flatpak apps see the GTK theme and our generated colors.
    run flatpak override --system --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro \
      --filesystem=/usr/share/themes:ro --filesystem=xdg-config/qt5ct:ro --filesystem=xdg-config/qt6ct:ro \
      --env=QT_QPA_PLATFORMTHEME=qt5ct || true
  fi
  return 0
}
