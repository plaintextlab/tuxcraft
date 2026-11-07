# shellcheck shell=bash
# Fallbacks for tools a distro does not package (mostly Debian stable).
# Each installs a static upstream release into /usr/local, only if the tool is missing.

_tmpdir() { mktemp -d /tmp/tuxcraft.XXXXXX; }
# Every upstream file is pinned and checksum-verified (data/downloads.tsv, lib/pins.sh).
pfetch() { run pin_get "$1" "$2"; }
_is_x86_64() { [[ $(uname -m) == x86_64 ]]; }

ensure_yazi() {
  command -v yazi >/dev/null && return 0; _is_x86_64 || return 0
  local t; t=$(_tmpdir)
  if pfetch yazi "$t/y.zip" &&
     (cd "$t" && unzip -q y.zip); then
    install -m755 "$t"/yazi-*/yazi "$t"/yazi-*/ya /usr/local/bin/ && upstream_ok yazi
  else warn "Could not install yazi"; fi
  rm -rf "$t"
}

ensure_rmpc() {
  has_word "$TUX_BUNDLES" music || return 0
  command -v rmpc >/dev/null && return 0; _is_x86_64 || return 0
  local t; t=$(_tmpdir)
  if pfetch rmpc "$t/r.tgz" &&
     tar -xzf "$t/r.tgz" -C "$t"; then
    install -m755 "$t/rmpc" /usr/local/bin/ && upstream_ok rmpc
    [[ -f $t/man/rmpc.1 ]] && install -Dm644 "$t/man/rmpc.1" /usr/local/share/man/man1/rmpc.1
    [[ -f $t/completions/rmpc.bash ]] && install -Dm644 "$t/completions/rmpc.bash" /usr/share/bash-completion/completions/rmpc
  else warn "Could not install rmpc"; fi
  rm -rf "$t"
}

# ble.sh (bash autosuggestions + syntax colours): no distro packages it. The release tarball is
# the built program; it is only copied into place (no install script runs).
ensure_blesh() {
  [[ -r /usr/local/share/blesh/ble.sh ]] && return 0
  local t; t=$(_tmpdir)
  local d
  if pfetch blesh "$t/b.txz" && tar -xJf "$t/b.txz" -C "$t" && d=$(dirname "$(compgen -G "$t/ble-*/ble.sh" | head -n1)") &&
     [[ -r $d/ble.sh ]]; then
    rm -rf /usr/local/share/blesh && mkdir -p /usr/local/share && cp -a "$d" /usr/local/share/blesh &&
      ok "ble.sh installed from upstream release"
  else warn "Could not install ble.sh (bash still works, without command hints)"; fi
  rm -rf "$t"
}

# wifitui: Wi-Fi TUI for NetworkManager (nicer than nmtui). Not packaged by any distro yet.
ensure_wifitui() {
  command -v wifitui >/dev/null && return 0
  _is_x86_64 || return 0
  local t; t=$(_tmpdir)
  if pfetch wifitui "$t/w.tgz" &&
     tar -xzf "$t/w.tgz" -C "$t" wifitui; then
    install -m755 "$t/wifitui" /usr/local/bin/ && upstream_ok wifitui
  else warn "Could not install wifitui; the network menu uses nmtui"; fi
  rm -rf "$t"
}

# version_ge A B : true when version A >= B
version_ge() { [[ $(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1) == "$2" ]]; }

# LazyVim needs Neovim >= 0.11 and tree-sitter CLI >= 0.25 (Debian 13: 0.10 / 0.22).
ensure_neovim() {
  local v
  # "|| true": with pipefail a missing command would fail the assignment and stop the install.
  v=$({ nvim --version 2>/dev/null || true; } | sed -n '1s/^NVIM v\([0-9.]*\).*/\1/p')
  _is_x86_64 || return 0
  if [[ -z $v ]] || ! version_ge "$v" 0.11; then
    local t; t=$(_tmpdir)
    if pfetch neovim "$t/n.tgz" &&
       rm -rf /opt/nvim && mkdir -p /opt/nvim && tar -xzf "$t/n.tgz" -C /opt/nvim --strip-components=1; then
      ln -sfn /opt/nvim/bin/nvim /usr/local/bin/nvim && ok "Neovim $(/opt/nvim/bin/nvim --version | head -n1) installed from upstream release"
    else warn "Could not install a recent Neovim; LazyVim needs 0.11+"; fi
    rm -rf "$t"
  fi
  v=$({ tree-sitter --version 2>/dev/null || true; } | awk '{print $2}')
  if [[ -z $v ]] || ! version_ge "$v" 0.25; then
    local t; t=$(_tmpdir)
    if pfetch tree-sitter "$t/t.zip" &&
       (cd "$t" && unzip -qo t.zip) && [[ -f $t/tree-sitter ]]; then
      install -m755 "$t/tree-sitter" /usr/local/bin/tree-sitter && ok "tree-sitter CLI installed from upstream release"
    else warn "Could not install the tree-sitter CLI (Neovim syntax parsers will not build)"; fi
    rm -rf "$t"
  fi
}

ensure_starship() {
  command -v starship >/dev/null && return 0; _is_x86_64 || return 0
  local t; t=$(_tmpdir)
  if pfetch starship "$t/s.tgz"; then
    tar -xzf "$t/s.tgz" -C "$t" && install -m755 "$t/starship" /usr/local/bin/ && upstream_ok starship
  else warn "Could not install starship"; fi
  rm -rf "$t"
}

ensure_bluetui() {
  command -v bluetui >/dev/null && return 0; _is_x86_64 || return 0
  if pfetch bluetui /usr/local/bin/bluetui && chmod 755 /usr/local/bin/bluetui; then upstream_ok bluetui
  else warn "Could not install bluetui"; fi
}

ensure_lazygit() {
  command -v lazygit >/dev/null && return 0; _is_x86_64 || return 0
  local t; t=$(_tmpdir)
  if pfetch lazygit "$t/l.tgz" && tar -xzf "$t/l.tgz" -C "$t" lazygit; then
    install -m755 "$t/lazygit" /usr/local/bin/ && upstream_ok lazygit
  else warn "Could not install lazygit"; fi
  rm -rf "$t"
}

# adw-gtk3: makes GTK3 apps look like libadwaita/GTK4 apps, so one palette themes both.
ensure_adw_gtk3() {
  [[ -d /usr/share/themes/adw-gtk3-dark ]] && return 0
  local t; t=$(_tmpdir)
  if pfetch adw-gtk3 "$t/a.txz"; then
    tar -xJf "$t/a.txz" -C /usr/share/themes && upstream_ok adw-gtk3
  else warn "Could not install adw-gtk3; GTK3 apps fall back to Adwaita"; fi
  rm -rf "$t"
}

ensure_papirus_folders() {
  command -v papirus-folders >/dev/null && return 0
  if pfetch papirus-folders /usr/local/bin/papirus-folders; then chmod 755 /usr/local/bin/papirus-folders
  else warn "Could not install papirus-folders"; fi
}

# Debian ships fd and bat under other names.
ensure_debian_shims() {
  [[ $DISTRO == debian ]] || return 0
  command -v fd  >/dev/null || { command -v fdfind >/dev/null && ln -sf "$(command -v fdfind)" /usr/local/bin/fd; }
  command -v bat >/dev/null || { command -v batcat >/dev/null && ln -sf "$(command -v batcat)" /usr/local/bin/bat; }
  # Debian's imv has only imv-x11 / imv-wayland on PATH; the launcher that picks one is in libexec.
  command -v imv >/dev/null || { [[ -x /usr/libexec/imv/imv ]] && ln -sf /usr/libexec/imv/imv /usr/local/bin/imv; }
  return 0
}

ensure_paru() {
  [[ $DISTRO == arch ]] || return 0
  command -v paru >/dev/null && return 0
  info "Building paru (AUR helper) as $TUX_USER"
  local t; t=$(_tmpdir); chown "$TUX_USER" "$t"
  if run as_user git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$t/paru-bin" &&
     run as_user sh -c "cd '$t/paru-bin' && makepkg --noconfirm"; then
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

# Gaming bundle: system limits Proton and newer games need, gamemode priority, Heroic, and the
# Flatpak NVIDIA runtime so Flatpak games get the GPU.
ensure_gaming() {
  has_word "$TUX_BUNDLES" gaming || return 0
  step "Gaming setup"
  mkdir -p /etc/sysctl.d /etc/security/limits.d
  # The 65530 default makes many newer games crash; this is the SteamOS value.
  printf '# tuxcraft: games/Proton need many memory mappings (SteamOS value)\nvm.max_map_count = 2147483642\n' \
    >/etc/sysctl.d/80-tuxcraft-gaming.conf
  # Proton/Wine esync opens one file descriptor per sync object.
  printf '# tuxcraft: Proton/Wine esync\n*  soft  nofile  524288\n*  hard  nofile  524288\n' \
    >/etc/security/limits.d/20-tuxcraft-gaming.conf
  # gamemode's limits.d entry (renice) only applies to members of its group.
  getent group gamemode >/dev/null && usermod -aG gamemode "$TUX_USER"
  # Lutris and the Steam runtime look 32-bit libraries up in the ld.so cache; after the
  # -32bit packages it was found stale (libdrm.so.2 missing), so rebuild it.
  run ldconfig || true

  command -v flatpak >/dev/null || pkg_install flatpak
  command -v flatpak >/dev/null || { warn "flatpak missing: Heroic not installed"; return 0; }
  run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
  run flatpak install -y --noninteractive flathub com.heroicgameslauncher.hgl || warn "Heroic could not be installed"
  flatpak_nvidia_runtime
  info "Gaming: Steam launch option  gamemoderun mangohud %command%"
}

extras_stage() {
  step "Filling gaps with upstream releases where needed"
  ensure_debian_shims
  ensure_yazi
  ensure_starship
  ensure_rmpc
  ensure_blesh
  ensure_wifitui
  ensure_neovim
  ensure_lazygit
  [[ ${HAS_BT:-0} == 1 ]] || has_word "$TUX_BUNDLES" bluetooth && ensure_bluetui
  ensure_adw_gtk3
  ensure_papirus_folders
  has_word "$TUX_BUNDLES" aur && ensure_paru
  has_word "$TUX_EXCLUDE" copyq || ensure_clipboard
  ensure_gaming
  if has_word "$TUX_BUNDLES" flatpak && command -v flatpak >/dev/null; then
    run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    # Let flatpak apps see the GTK theme and our generated colors.
    run flatpak override --system --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro \
      --filesystem=/usr/share/themes:ro --filesystem=xdg-config/qt5ct:ro --filesystem=xdg-config/qt6ct:ro \
      --env=QT_QPA_PLATFORMTHEME=qt5ct || true
    flatpak_nvidia_runtime
  fi
  return 0
}

# Flatpak apps get the NVIDIA driver from a runtime matching the host driver exactly
# (GL.nvidia-595-112-07). Flatpak adds it by itself only when the nvidia module is loaded, which
# it is not while installing from a live ISO; so install it now for the driver that boots next,
# and OBS, Steam, Blender or games installed later have NVENC/CUDA/GL out of the box.
# (sysup keeps it in step after driver updates; nvidia_uvm_setup provides /dev/nvidia-uvm.)
flatpak_nvidia_runtime() {
  [[ ${TUX_NVIDIA:-no} == yes ]] && command -v flatpak >/dev/null || return 0
  local nv ext kver
  kver=$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -V | tail -n1)
  nv=$(modinfo -k "$kver" -F version nvidia 2>/dev/null || true)
  [[ -n $nv ]] || return 0
  for ext in GL GL32; do
    flatpak info "org.freedesktop.Platform.$ext.nvidia-${nv//./-}" >/dev/null 2>&1 ||
      run flatpak install -y --noninteractive flathub "org.freedesktop.Platform.$ext.nvidia-${nv//./-}" ||
      warn "Flatpak NVIDIA $ext runtime $nv not on Flathub yet (sysup installs it later)"
  done
  return 0
}
