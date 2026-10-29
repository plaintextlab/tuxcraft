# shellcheck shell=bash
# The desktop: packages, tuxcraft runtime, dotfiles, login screen, theme.

desktop_packages() {
  step "Desktop packages ($TUX_SESSION)"
  local groups="core tui"
  [[ $TUX_SESSION == sway ]] && groups+=' wayland' || groups+=' x11'
  local b
  for b in firewall music firefox chromium dev flatpak printing gaming office; do
    has_word "$TUX_BUNDLES" "$b" && groups+=" $b"
  done
  { [[ ${HAS_BT:-0} == 1 ]] || has_word "$TUX_BUNDLES" bluetooth; } && groups+=' bluetooth'
  [[ ${IS_LAPTOP:-0} == 1 ]] && groups+=' laptop'
  # shellcheck disable=SC2086
  pkg_install_groups $groups
  # shellcheck disable=SC2086
  [[ -n ${TUX_EXTRA:-} ]] && pkg_install $TUX_EXTRA
  return 0
}

install_runtime() {
  step "Installing tuxcraft tools"
  if [[ $(readlink -f "$TUX_SRC") != "$TUX_SHARE" ]]; then
    rm -rf "$TUX_SHARE"; mkdir -p "$TUX_SHARE"
    cp -a "$TUX_SRC"/. "$TUX_SHARE"/
    rm -rf "$TUX_SHARE/.git"
  fi
  local f
  for f in "$TUX_SHARE"/bin/*; do install -m755 "$f" "/usr/local/bin/$(basename "$f")"; done
  mkdir -p "$TUX_ETC"
  cat >"$TUX_ETC/session.conf" <<EOF
# Written by tuxcraft. tux-session reads this at login.
SESSION=$TUX_SESSION
NVIDIA=${TUX_NVIDIA:-no}
DISTRO=$DISTRO
BROWSER=${TUX_BROWSER:-firefox}
KEYMAP=$TUX_KEYMAP
EOF
  # Let wheel users re-theme the login screen/TTY without a password prompt.
  echo '%wheel ALL=(root) NOPASSWD: /usr/local/bin/tux-theme-system' >/etc/sudoers.d/20-tuxcraft-theme
  chmod 440 /etc/sudoers.d/20-tuxcraft-theme
}

void_pipewire() {
  [[ $DISTRO == void ]] || return 0
  # Void has no systemd user units: pipewire starts wireplumber + pulse shim itself.
  mkdir -p /etc/pipewire/pipewire.conf.d /etc/alsa/conf.d
  ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf /etc/pipewire/pipewire.conf.d/
  ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf /etc/pipewire/pipewire.conf.d/
  ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf /etc/alsa/conf.d/ 2>/dev/null || true
  ln -sf /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf /etc/alsa/conf.d/ 2>/dev/null || true
}

desktop_services() {
  has_word "$TUX_BUNDLES" printing && { usermod -aG lp "$TUX_USER" 2>/dev/null || true; }
  local g
  for g in docker lpadmin video input; do getent group "$g" >/dev/null && usermod -aG "$g" "$TUX_USER"; done
  if [[ $INIT == systemd ]]; then
    pkg_installed bluez && svc_enable bluetooth
    has_word "$TUX_BUNDLES" printing && svc_enable cups avahi-daemon
    has_word "$TUX_BUNDLES" dev && svc_enable docker
    [[ ${IS_LAPTOP:-0} == 1 ]] && svc_enable power-profiles-daemon
  else
    pkg_installed bluez && svc_enable bluetoothd
    has_word "$TUX_BUNDLES" printing && svc_enable cupsd avahi-daemon
    has_word "$TUX_BUNDLES" dev && svc_enable docker
    [[ ${IS_LAPTOP:-0} == 1 ]] && svc_enable power-profiles-daemon
  fi
  if has_word "$TUX_BUNDLES" firewall; then
    local fw=(on); [[ $TUX_MODE == install ]] && fw+=(--boot-only)
    /usr/local/bin/tux-firewall "${fw[@]}" >>"$TUX_LOG" 2>&1 || warn "Could not set up the firewall"
  fi
  # Tap-to-click and natural behaviour on touchpads (from debi3n touchpad-setup.sh)
  if [[ ${IS_LAPTOP:-0} == 1 ]]; then
    mkdir -p /etc/X11/xorg.conf.d
    cat >/etc/X11/xorg.conf.d/30-touchpad.conf <<'EOF'
Section "InputClass"
    Identifier "libinput touchpad"
    MatchIsTouchpad "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "Tapping" "on"
    Option "TappingButtonMap" "lrm"
    Option "DisableWhileTyping" "on"
EndSection
EOF
  fi
  return 0
}

greeter_user() {
  local u
  u=$(sed -n 's/^user *= *"\(.*\)"/\1/p' /etc/greetd/config.toml 2>/dev/null | head -n1)
  [[ -n $u ]] && { echo "$u"; return; }
  for u in greeter _greetd _greeter; do getent passwd "$u" >/dev/null && { echo "$u"; return; }; done
  useradd -r -M -s /usr/sbin/nologin -G video greeter 2>/dev/null; echo greeter
}

greeter_stage() {
  step "Login screen"
  local dm
  for dm in lightdm gdm gdm3 sddm lxdm ly display-manager; do svc_disable "$dm"; done
  if command -v tuigreet >/dev/null; then
    local gu; gu=$(greeter_user)
    mkdir -p /etc/greetd /var/cache/tuigreet
    chown "$gu" /var/cache/tuigreet 2>/dev/null || true
    # Runs on its own VT so boot messages on tty1 never garble the prompt.
    cat >/etc/greetd/config.toml <<EOF
# tuxcraft: TUI login (tuigreet). Colours follow the system theme via the console palette.
[terminal]
vt = 7

[default_session]
command = "tuigreet --time --remember --asterisks --window-padding 2 --container-padding 2 --greeting 'Welcome to $TUX_HOSTNAME' --theme 'border=yellow;title=yellow;greet=white;text=white;prompt=yellow;input=white;time=bright-black;action=bright-black;button=yellow;container=black' --cmd tux-session"
user = "$gu"
EOF
    svc_enable greetd
    ok "greetd + tuigreet enabled (F2: commands, F3: pick session, F12: power)"
  else
    warn "tuigreet not available, falling back to LightDM"
    pkg_install lightdm lightdm-gtk-greeter
    svc_enable lightdm
  fi
  # Session entries so any display manager (and tuigreet's F3 menu) can start tuxcraft.
  mkdir -p /usr/share/xsessions /usr/share/wayland-sessions
  printf '[Desktop Entry]\nName=tuxcraft (i3)\nExec=tux-session i3\nType=Application\n' >/usr/share/xsessions/tuxcraft-i3.desktop
  printf '[Desktop Entry]\nName=tuxcraft (sway)\nExec=tux-session sway\nType=Application\n' >/usr/share/wayland-sessions/tuxcraft-sway.desktop
  # Console palette at boot (themed TTY + greeter)
  if [[ $INIT == systemd ]]; then
    cat >/etc/systemd/system/tuxcraft-vtrgb.service <<'EOF'
[Unit]
Description=tuxcraft console colour palette
ConditionPathExists=/etc/tuxcraft/vtrgb
Before=greetd.service getty@tty1.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'setvtrgb /etc/tuxcraft/vtrgb'

[Install]
WantedBy=multi-user.target
EOF
    svc_enable tuxcraft-vtrgb.service
  else
    touch /etc/rc.local
    grep -q tuxcraft/vtrgb /etc/rc.local || echo '[ -f /etc/tuxcraft/vtrgb ] && setvtrgb /etc/tuxcraft/vtrgb' >>/etc/rc.local
  fi
}

# Copy dotfiles into $HOME. Anything already there that would be overwritten is
# moved to ~/.local/state/tuxcraft/backup-<date>/ first — nothing is silently lost.
deploy_dotfiles() {
  step "Placing configs in $TUX_HOME"
  local src="$TUX_SHARE/dotfiles" backup rel dst
  backup="$TUX_HOME/.local/state/tuxcraft/backup-$(date +%Y%m%d-%H%M%S)"
  while IFS= read -r -d '' f; do
    rel=${f#"$src"/}
    dst="$TUX_HOME/$rel"
    [[ $rel == */local.d/* && -e $dst ]] && continue   # user overrides are theirs
    if [[ -e $dst ]] && ! cmp -s "$f" "$dst"; then
      mkdir -p "$backup/$(dirname "$rel")"
      mv "$dst" "$backup/$rel"
    fi
    install -D -m "$(stat -c %a "$f")" "$f" "$dst"
  done < <(find "$src" -type f -print0)
  [[ -d $backup ]] && info "Previous configs saved in ${backup/#$TUX_HOME/\~}"

  # Keyboard layout for sway (X11 reads /etc/X11/xorg.conf.d)
  mkdir -p "$TUX_HOME/.config/sway"
  printf 'input type:keyboard {\n    xkb_layout %s\n    xkb_numlock enabled\n}\ninput type:touchpad {\n    tap enabled\n    natural_scroll disabled\n    dwt enabled\n}\n' \
    "$TUX_KEYMAP" >"$TUX_HOME/.config/sway/input.conf"

  # Remember the choices so tux-theme/tux-font can re-render later.
  mkdir -p "$TUX_HOME/.config/tuxcraft"
  local fam term_fam
  fam=$(font_field "$TUX_FONT" 2)
  term_fam=$fam
  [[ $TUX_FONT == noto ]] && term_fam=$(font_field jetbrains 2)
  cat >"$TUX_HOME/.config/tuxcraft/state" <<EOF
THEME=$TUX_THEME
FONT="$fam"
TERM_FONT="$term_fam"
FONT_SIZE=${TUX_FONT_SIZE:-11}
TERM_FONT_SIZE=${TUX_TERM_FONT_SIZE:-12}
BROWSER=${TUX_BROWSER:-firefox}
WALLPAPER=theme
EOF
  chown -R "$TUX_USER:" "$TUX_HOME/.config" "$TUX_HOME/.local" "$TUX_HOME"/.[!.]* 2>/dev/null || true
}

wallpapers_stage() {
  local dir="$TUX_HOME/Pictures/Wallpapers"
  mkdir -p "$dir"
  if has_word "$TUX_BUNDLES" wallpapers; then
    info "Fetching the debi3n wallpaper pack (~320 MB)"
    local t; t=$(mktemp -d)
    if run git clone --depth 1 --filter=blob:none --sparse https://github.com/plaintextlab/debi3n "$t/d" &&
       run git -C "$t/d" sparse-checkout set dots/wallpapers; then
      cp -n "$t"/d/dots/wallpapers/Pictures/Wallpapers/* "$dir"/ 2>/dev/null || true
    else
      warn "Wallpaper download failed; theme wallpapers are still generated."
    fi
    rm -rf "$t"
  fi
  chown -R "$TUX_USER:" "$TUX_HOME/Pictures"
}

default_apps() {
  local m b
  b=${TUX_BROWSER:-firefox}
  case $b in firefox) b=$( [[ $DISTRO == debian ]] && echo firefox-esr || echo firefox ) ;; esac
  as_user xdg-user-dirs-update >/dev/null 2>&1 || true
  for m in image/png image/jpeg image/gif image/webp image/bmp image/tiff image/svg+xml; do
    as_user xdg-mime default imv.desktop "$m" 2>/dev/null || true
  done
  for m in video/mp4 video/x-matroska video/webm audio/mpeg audio/flac audio/ogg; do
    as_user xdg-mime default mpv.desktop "$m" 2>/dev/null || true
  done
  command -v zathura >/dev/null && as_user xdg-mime default org.pwmt.zathura.desktop application/pdf 2>/dev/null
  [[ $b != none ]] && as_user xdg-settings set default-web-browser "$b.desktop" 2>/dev/null
  as_user xdg-mime default thunar.desktop inode/directory 2>/dev/null
  return 0
}

theme_stage() {
  step "Applying theme '$TUX_THEME' system-wide"
  /usr/local/bin/tux-theme-system "$TUX_THEME" || warn "System theme step failed"
  as_user /usr/local/bin/tux-theme apply || warn "tux-theme apply failed (see $TUX_LOG)"
}

desktop_stage() {
  desktop_packages
  extras_stage
  install_runtime
  void_pipewire
  desktop_services
  fonts_stage
  deploy_dotfiles
  wallpapers_stage
  greeter_stage
  theme_stage
  default_apps
}
