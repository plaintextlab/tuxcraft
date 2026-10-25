#!/usr/bin/env bash
# tuxcraft — one script from a live ISO (or a minimal install) to a complete i3/sway desktop.
#
#   From a live ISO (Arch / Debian live / Void):   erases a disk, installs everything
#   From an installed system:                       sets up the desktop on top of it
#
#   curl -fsSL https://raw.githubusercontent.com/plaintextlab/tuxcraft/main/install.sh | sudo bash
#   sudo ./install.sh [--config answers.conf] [--yes] [--desktop]
set -Eeuo pipefail
umask 022   # an inherited 077 would leave / and /home unreadable to the new user

TUX_REPO_TARBALL=${TUX_REPO_TARBALL:-https://github.com/plaintextlab/tuxcraft/archive/refs/heads/main.tar.gz}

# --- self-bootstrap when piped through curl -------------------------------------------
TUX_SRC=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo /tmp)
if [[ ! -f $TUX_SRC/lib/ui.sh ]]; then
  echo ":: Downloading tuxcraft..."
  rm -rf /tmp/tuxcraft && mkdir -p /tmp/tuxcraft
  curl -fsSL "$TUX_REPO_TARBALL" | tar -xz -C /tmp/tuxcraft --strip-components=1
  exec bash /tmp/tuxcraft/install.sh "$@" </dev/tty
fi

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [options]

  --config FILE   read answers from FILE (any question answered there is skipped)
  --yes           accept defaults for anything not in the answers file
  --desktop       set up the desktop on this running system even if it looks like a live ISO
  -h, --help      this help

Answer keys (see README): TUX_DISK TUX_HOSTNAME TUX_USER TUX_PASSWORD TUX_TIMEZONE TUX_LOCALE
TUX_KEYMAP TUX_SESSION TUX_NVIDIA TUX_THEME TUX_FONT TUX_FONT_SIZE TUX_BROWSER TUX_BUNDLES
TUX_EXTRA TUX_EXCLUDE
EOF
}

STAGE=wizard FORCE_DESKTOP=0 CONFIG=''
ORIG_ARGS=("$@")
while (($#)); do
  case $1 in
    --config) CONFIG=$2; shift ;;
    --yes|-y) export TUX_YES=1 ;;
    --desktop) FORCE_DESKTOP=1 ;;
    --stage) STAGE=$2; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ $EUID -ne 0 ]]; then
  exec sudo -E bash "$0" "${ORIG_ARGS[@]}"
fi

for f in ui core pkg disk bootstrap system gpu extras fonts desktop snapshots; do
  # shellcheck source=/dev/null
  . "$TUX_SRC/lib/$f.sh"
done

trap 'warn "Failed at line $LINENO: $BASH_COMMAND (full log: $TUX_LOG)"' ERR
mkdir -p "$(dirname "$TUX_LOG")"

# shellcheck source=/dev/null
[[ -n $CONFIG ]] && . "$CONFIG"

ANSWER_KEYS=(TUX_MODE TUX_DISK TUX_HOSTNAME TUX_USER TUX_TIMEZONE TUX_LOCALE TUX_KEYMAP TUX_SESSION
             TUX_NVIDIA TUX_THEME TUX_FONT TUX_FONT_SIZE TUX_BROWSER TUX_BUNDLES TUX_EXTRA TUX_EXCLUDE BOOT_MODE)

save_answers() {  # never stores the password
  local k
  mkdir -p "$(dirname "$1")"
  { echo "# tuxcraft answers — reuse with: sudo ./install.sh --config this-file"
    for k in "${ANSWER_KEYS[@]}"; do printf '%s=%q\n' "$k" "${!k:-}"; done; } >"$1"
  chmod 600 "$1"
}

guess_timezone() {
  local tz
  tz=$(curl -fsS --max-time 4 https://ipapi.co/timezone 2>/dev/null || true)
  [[ $tz =~ ^[A-Za-z_]+/[A-Za-z_/+-]+$ ]] || tz=$(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')
  echo "${tz:-UTC}"
}

theme_choices() {
  local f n
  for f in "$TUX_SRC"/themes/*.theme; do
    n=$(sed -n 's/^name="\(.*\)"/\1/p' "$f")
    echo "$(basename "$f" .theme)|$n|$(sed -n '1s/^# *//p' "$f")"
  done
}

preview_fonts() {
  # Real previews need a graphical session; on a bare TTY we can only describe them.
  local img="$TUX_SRC/assets/font-previews/all.png"
  [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} && -f $img ]] || {
    info "Font previews: open $TUX_SRC/assets/font-previews/all.png, or run 'tux-font' after install for live previews."
    return 0
  }
  local v
  for v in imv feh xdg-open; do
    command -v "$v" >/dev/null && { runuser -u "${SUDO_USER:-root}" -- "$v" "$img" >/dev/null 2>&1 & return 0; }
  done
}

wizard() {
  clear || true
  banner
  info "Detected: $DISTRO_ID, ${BOOT_MODE^^} boot, GPU: ${GPU_VENDORS:-none}$( ((IS_LAPTOP)) && echo ', laptop')"

  if [[ -z ${TUX_MODE:-} ]]; then
    if ((IS_LIVE)) && ((!FORCE_DESKTOP)); then
      choose TUX_MODE "You are on a live system. What should tuxcraft do?" install \
        "install|Install to a disk|erase a disk, install $DISTRO + desktop" \
        "desktop|Set up this system|only if this is NOT the live ISO"
    else
      TUX_MODE=desktop
    fi
  fi

  if [[ $TUX_MODE == install ]]; then
    pick_disk
    ask TUX_HOSTNAME "Computer name" tuxbox
    ask TUX_USER "Your username" "${SUDO_USER:-user}"
    [[ $TUX_USER =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username '$TUX_USER'"
    if [[ -z ${TUX_PASSWORD:-} ]]; then
      [[ -n ${TUX_YES:-} ]] && die "TUX_PASSWORD must be set for unattended installs"
      ask_secret TUX_PASSWORD "Password for $TUX_USER (also used for sudo)"
    fi
    ask TUX_TIMEZONE "Timezone" "$(guess_timezone)"
    ask TUX_LOCALE "Locale" en_US.UTF-8
    ask TUX_KEYMAP "Keyboard layout (xkb: us, de, gb, fr, ...)" us
  else
    ask TUX_USER "Which user gets the desktop?" "${SUDO_USER:-}"
    id "$TUX_USER" &>/dev/null || die "User $TUX_USER does not exist"
    TUX_HOSTNAME=${TUX_HOSTNAME:-$(cat /etc/hostname 2>/dev/null || echo linux)}
    ask TUX_KEYMAP "Keyboard layout (xkb: us, de, gb, fr, ...)" \
      "$(sed -n 's/.*XkbLayout" *"\([^"]*\)".*/\1/p' /etc/X11/xorg.conf.d/00-keyboard.conf 2>/dev/null | head -n1 || true)"
    TUX_KEYMAP=${TUX_KEYMAP:-us}
  fi

  local nv_note=''
  has_word "$GPU_VENDORS" nvidia && nv_note=' (sway on NVIDIA works, but i3 is smoother)'
  choose TUX_SESSION "Display server$nv_note" i3 \
    "i3|X11 + i3|most compatible: screen sharing, games, old apps just work" \
    "sway|Wayland + sway|same keys & look, smoother, tear-free, newer"

  if has_word "$GPU_VENDORS" nvidia; then
    choose TUX_NVIDIA "NVIDIA GPU found ($NVIDIA_GEN). Install the proprietary driver?" yes \
      "yes|Yes, proprietary|best performance, CUDA, gaming" \
      "no|No, keep nouveau|open source, slower, fine for desktop use"
  else
    TUX_NVIDIA=no
  fi

  local -a opts
  mapfile -t opts < <(theme_choices)
  choose TUX_THEME "Colour scheme (applies to everything: WM, bar, terminal, GTK, Qt, login, TTY)" gruvbox "${opts[@]}"

  preview_fonts
  mapfile -t opts < <(font_choices)
  choose TUX_FONT "UI font (Nerd Font icons are added to every choice automatically)" jetbrains "${opts[@]}"
  ask TUX_FONT_SIZE "UI font size" 11

  choose TUX_BROWSER "Web browser" firefox \
    "firefox|Firefox|" "chromium|Chromium|" "none|None|install your own later"
  [[ $TUX_BROWSER == none ]] || TUX_BUNDLES_BROWSER=$TUX_BROWSER

  local bt=off aur=off
  ((HAS_BT)) && bt=on
  [[ $DISTRO == arch ]] && aur=on
  checklist TUX_BUNDLES "Optional extras" \
    "gui-fm|Nemo file manager|on|GUI file manager next to yazi (drag & drop)" \
    "flatpak|Flatpak + Flathub|on|sandboxed apps, themed like the rest" \
    "wallpapers|debi3n wallpapers|on|~320 MB pack from plaintextlab/debi3n" \
    "bluetooth|Bluetooth|$bt|bluez + bluetui" \
    "music|Music (mpd+ncmpcpp)|off|TUI music player" \
    "printing|Printing|off|CUPS + network printer discovery" \
    "dev|Developer tools|off|docker, lazydocker, node, go, rust, python" \
    "office|Office & PDF|off|LibreOffice + zathura" \
    "gaming|Gaming|off|Steam, gamemode, MangoHud (enables multilib)" \
    "aur|AUR helper (paru)|$aur|Arch only"
  [[ -n ${TUX_BUNDLES_BROWSER:-} ]] && TUX_BUNDLES+=" $TUX_BUNDLES_BROWSER"

  if [[ -z ${TUX_YES:-} ]]; then
    [[ -v TUX_EXTRA ]] || read -r -e -p "${C_BOLD}? Extra packages to install${C_RESET} ${C_DIM}(space separated, Enter for none)${C_RESET} " TUX_EXTRA </dev/tty
    [[ -v TUX_EXCLUDE ]] || read -r -e -p "${C_BOLD}? Packages to leave out${C_RESET} ${C_DIM}(e.g. picom copyq, Enter for none)${C_RESET} " TUX_EXCLUDE </dev/tty
  fi
  TUX_EXTRA=${TUX_EXTRA:-} TUX_EXCLUDE=${TUX_EXCLUDE:-}

  printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-12s %s\n' Mode "$TUX_MODE" Distro "$DISTRO" User "$TUX_USER" Session "$TUX_SESSION" \
    NVIDIA "$TUX_NVIDIA" Theme "$TUX_THEME" Font "$(font_field "$TUX_FONT" 2) $TUX_FONT_SIZE" \
    Browser "$TUX_BROWSER" Extras "${TUX_BUNDLES:-none}"
  [[ $TUX_MODE == install ]] && printf '  %-12s %s\n' Disk "$TUX_DISK (ERASED, btrfs + snapshots)" Host "$TUX_HOSTNAME" \
    Timezone "$TUX_TIMEZONE" Locale "$TUX_LOCALE" Keyboard "$TUX_KEYMAP"
  [[ -n $TUX_EXTRA ]] && printf '  %-12s %s\n' "+ packages" "$TUX_EXTRA"
  [[ -n $TUX_EXCLUDE ]] && printf '  %-12s %s\n' "- packages" "$TUX_EXCLUDE"
  echo
  confirm "Start?" y || die "Aborted, nothing was changed."
  [[ $TUX_MODE == install ]] && confirm_wipe
  return 0
}

# Runs on the final system: inside the chroot for fresh installs, directly otherwise.
target_stage() {
  export TUX_USER
  if [[ $TUX_MODE == install ]]; then
    system_stage
  else
    pkg_refresh
    sys_pkgmanager
  fi
  # Only now: on a fresh install the user is created by system_stage.
  TUX_HOME=$(getent passwd "$TUX_USER" | cut -d: -f6)
  export TUX_HOME
  gpu_stage
  desktop_stage
  snapshots_stage
  if [[ $TUX_MODE == install ]]; then
    sys_bootloader
  elif [[ -f /etc/grub.d/41_snapshots-btrfs ]] && command -v grub-mkconfig >/dev/null; then
    run grub-mkconfig -o /boot/grub/grub.cfg || warn "grub-mkconfig failed"
  fi
  snapshots_baseline
  save_answers "$TUX_ETC/answers.conf"
  if [[ -n ${PKG_MISSING// } ]]; then
    warn "Not available on $DISTRO and skipped:${PKG_MISSING}"
  fi
}

main() {
  detect_all
  if [[ $STAGE == target ]]; then
    # shellcheck source=/dev/null
    . "$TUX_ETC/answers.conf"
    target_stage
    exit 0
  fi

  wizard
  local start=$SECONDS
  if [[ $TUX_MODE == install ]]; then
    disk_prepare
    bootstrap_base
    step "Handing over to the new system"
    mkdir -p "$TARGET$TUX_SHARE" "$TARGET$TUX_ETC"
    cp -a "$TUX_SRC"/. "$TARGET$TUX_SHARE"/
    save_answers "$TARGET$TUX_ETC/answers.conf"
    chroot "$TARGET" /usr/bin/env TUX_PASSWORD="$TUX_PASSWORD" TUX_LOG=/var/log/tuxcraft.log \
      TUX_YES="${TUX_YES:-}" bash "$TUX_SHARE/install.sh" --stage target || die "Setup inside the new system failed. Log: $TARGET/var/log/tuxcraft.log"
    cat "$TUX_LOG" >>"$TARGET/var/log/tuxcraft-live.log" 2>/dev/null || true
    sync
    umount -R "$TARGET" 2>/dev/null || warn "Could not unmount $TARGET cleanly"
  else
    TUX_SRC=$TUX_SRC target_stage
  fi

  printf '\n%s  Done in %d min.%s\n\n' "$C_GREEN$C_BOLD" $(((SECONDS - start) / 60)) "$C_RESET"
  cat <<EOF
  Next steps
    • Log in on the TUI login screen. Super+K shows every keybinding.
    • tux-theme / tux-font      change colours / font anytime (Super+Ctrl+T / Super+Ctrl+F)
    • sysup                     the ONE way to update: snapshots, news check, cleanup
    • tux-snap                  list / create / roll back snapshots
    • Full log: /var/log/tuxcraft.log
EOF
  if [[ $TUX_MODE == install ]]; then
    confirm "Reboot now?" y && reboot
  else
    info "Log out and back in (or reboot) to start the new session."
  fi
}

main
