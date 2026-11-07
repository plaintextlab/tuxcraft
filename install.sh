#!/usr/bin/env bash
# tuxcraft — one script from a live ISO (or a minimal install) to a complete i3/sway desktop.
#
#   From a live ISO (Arch / Debian live / Void):   erases a disk, installs everything
#   From an installed system:                       sets up the desktop on top of it
#
#   curl -fsSL https://plaintextlab.org/tuxcraft | sh                 (Arch)
#   wget -nv -O- https://plaintextlab.org/tuxcraft | sh              (Debian live)
#   xbps-fetch -o t https://plaintextlab.org/tuxcraft && sh t         (Void)
#   (the same with https://raw.githubusercontent.com/plaintextlab/tuxcraft/main/install.sh)
#   sudo ./install.sh [--config answers.conf] [--yes] [--desktop]
#
# --- bootstrap ------------------------------------------------------------------------------
# Plain POSIX sh up to the "exec bash" lines: "curl ... | sh" runs this under dash on Debian and
# Void. No git needed: the repository comes as a tarball, with whatever download tool the live
# ISO has (curl on Arch, wget on Debian live, xbps-fetch on Void). sh reads a piped script one
# command at a time, so the bash-only code below is never parsed by it.
#
# Release builds of this file (the install.sh attached to each GitHub release, which is what
# https://plaintextlab.org/tuxcraft serves) have the two lines below rewritten by
# .github/workflows/release.yml to that release's tarball and its SHA-256, so what runs as root
# is exactly the tagged release. This copy on the main branch follows main, unverified: the
# development channel.
TUX_REPO_TARBALL=${TUX_REPO_TARBALL:-https://github.com/plaintextlab/tuxcraft/archive/refs/heads/main.tar.gz}
TUX_REPO_SHA256=${TUX_REPO_SHA256:-}
TUX_SRC=
[ -f "$0" ] && TUX_SRC=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
if [ ! -f "$TUX_SRC/lib/ui.sh" ]; then
  # Piped from the internet (or a lone install.sh): fetch the rest.
  echo ":: Downloading tuxcraft..."
  dl=/tmp/tuxcraft; rm -rf "$dl" "$dl.tar.gz" && mkdir -p "$dl" || exit 1
  if command -v curl >/dev/null; then curl -fsSL -o "$dl.tar.gz" "$TUX_REPO_TARBALL"
  elif command -v wget >/dev/null; then wget -qO "$dl.tar.gz" "$TUX_REPO_TARBALL"
  elif command -v xbps-fetch >/dev/null; then xbps-fetch -o "$dl.tar.gz" "$TUX_REPO_TARBALL" >/dev/null
  else echo "Need curl, wget or xbps-fetch to download tuxcraft" >&2; exit 1; fi || {
    echo "Download failed. Connected to the internet? Wi-Fi: see 'Connecting to the internet' in the README" >&2; exit 1; }
  if [ -n "$TUX_REPO_SHA256" ]; then
    echo "$TUX_REPO_SHA256  $dl.tar.gz" | sha256sum -c - >/dev/null 2>&1 || {
      echo "CHECKSUM MISMATCH: the downloaded tuxcraft is not the published release. Stopping." >&2; exit 1; }
  fi
  tar -xzf "$dl.tar.gz" -C "$dl" --strip-components=1 || { echo "Download was not a tuxcraft archive" >&2; exit 1; }
  command -v bash >/dev/null || { echo "tuxcraft needs bash" >&2; exit 1; }
  # stdin is the download pipe: answer the questions from the keyboard instead.
  if (exec </dev/tty) 2>/dev/null; then exec bash "$dl/install.sh" "$@" </dev/tty; fi
  exec bash "$dl/install.sh" "$@"
fi
# Started as "sh install.sh": the rest is bash.
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"
# --- from here on: bash ---------------------------------------------------------------------
set -Eeuo pipefail
umask 022   # an inherited 077 would leave / and /home unreadable to the new user

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [options]

  --config FILE   read answers from FILE (any question answered there is skipped)
  --yes           accept defaults for anything not in the answers file
  --desktop       set up the desktop on this running system even if it looks like a live ISO
  --no-reboot     do not reboot when the install is finished (unattended runs)
  --update        already set up: keep every saved answer, just bring tuxcraft up to date
  -h, --help      this help

Answer keys (see README): TUX_DISTRO TUX_TARGET TUX_DISK TUX_PART TUX_ENCRYPT TUX_LUKS_PASSWORD
TUX_HOSTNAME TUX_USER TUX_PASSWORD TUX_TIMEZONE TUX_GEOIP TUX_LOCALE TUX_KEYMAP TUX_SESSION
TUX_NVIDIA TUX_THEME TUX_FONT TUX_FONT_SIZE TUX_BROWSER TUX_BUNDLES TUX_EXTRA TUX_EXCLUDE
TUX_DEBIAN_SUITE TUX_POST_HOOK
EOF
}

STAGE=wizard FORCE_DESKTOP=0 CONFIG='' NO_REBOOT=0 UPDATE=0
ORIG_ARGS=("$@")
while (($#)); do
  case $1 in
    --config) CONFIG=$2; shift ;;
    --yes|-y) export TUX_YES=1 ;;
    --desktop) FORCE_DESKTOP=1 ;;
    --no-reboot) NO_REBOOT=1 ;;
    --update) UPDATE=1 ;;
    --stage) STAGE=$2; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ $EUID -ne 0 ]]; then
  exec sudo -E bash "$0" "${ORIG_ARGS[@]}"
fi

# The rest of tuxcraft downloads with curl; the Void and Debian live ISOs come without it.
if ! command -v curl >/dev/null; then
  echo ":: Installing curl..."
  if command -v xbps-install >/dev/null; then { xbps-install -Syu xbps && xbps-install -Sy curl; } >/dev/null
  elif command -v apt-get >/dev/null; then { apt-get update && apt-get install -y curl ca-certificates; } >/dev/null
  elif command -v pacman >/dev/null; then pacman -Sy --noconfirm curl >/dev/null
  fi || { echo "Could not install curl (network?)" >&2; exit 1; }
fi

for f in ui core pins pkg disk bootstrap system gpu hwfix extras fonts desktop snapshots; do
  # shellcheck source=/dev/null
  . "$TUX_SRC/lib/$f.sh"
done

# A failure inside run() would only show run's own "return" line: name the real command instead.
# Its output is already on screen above (with TUX_QUIET=1 the end of the log is shown instead).
on_error() {
  local rc=$1 line=$2 cmd=$3 src=${BASH_SOURCE[1]##*/}
  if [[ $cmd == 'return "$rc"' && -n ${TUX_LAST_RUN:-} ]]; then
    if [[ -n ${TUX_QUIET:-} ]]; then
      local tail; tail=$(tail -n 15 "$TUX_LOG" 2>/dev/null | sed 's/^/    /')
      printf '%s\n' "$tail" >&2
    fi
    warn "Failed (exit $rc): $TUX_LAST_RUN"
  else
    warn "Failed at $src line $line (exit $rc): $cmd"
  fi
  warn "Full log: $TUX_LOG"
}
trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR
mkdir -p "$(dirname "$TUX_LOG")"

# shellcheck source=/dev/null
[[ -n $CONFIG ]] && . "$CONFIG"

ANSWER_KEYS=(TUX_MODE TUX_DISTRO TUX_TARGET TUX_DISK TUX_PART TUX_ENCRYPT TUX_DEBIAN_SUITE TUX_HOSTNAME TUX_USER TUX_TIMEZONE TUX_LOCALE TUX_KEYMAP TUX_SESSION
             TUX_NVIDIA TUX_THEME TUX_FONT TUX_FONT_SIZE TUX_BROWSER TUX_BUNDLES TUX_EXTRA TUX_EXCLUDE BOOT_MODE)

save_answers() {  # never stores the passwords
  local k
  mkdir -p "$(dirname "$1")"
  { echo "# tuxcraft answers — reuse with: sudo ./install.sh --config this-file"
    for k in "${ANSWER_KEYS[@]}"; do
      # The disk by its by-id name: kernel names like nvme0n1 can change between boots.
      if [[ $k == TUX_DISK && -n ${TUX_DISK:-} ]]; then printf '%s=%q\n' "$k" "$(disk_stable_name "$TUX_DISK")"
      else printf '%s=%q\n' "$k" "${!k:-}"; fi
    done; } >"$1"
  chmod 600 "$1"
}

# Offline by default: the live system's own timezone. Looking it up online sends your IP address
# to ipapi.co, so that only happens when asked (TUX_GEOIP=yes, or "y" in the wizard).
guess_timezone() {
  local tz=''
  [[ ${TUX_GEOIP:-no} == yes ]] && tz=$(curl -fsS --max-time 4 https://ipapi.co/timezone 2>/dev/null || true)
  # The live ISO may have no /etc/localtime symlink; readlink failing must not trip the ERR trap.
  [[ $tz =~ ^[A-Za-z_]+/[A-Za-z_/+-]+$ ]] || tz=$({ readlink /etc/localtime || true; } 2>/dev/null | sed 's#.*/zoneinfo/##')
  echo "${tz:-UTC}"
}

theme_choices() {
  local f n
  for f in "$TUX_SRC"/themes/*.theme; do
    n=$(sed -n 's/^name="\(.*\)"/\1/p' "$f")
    echo "$(basename "$f" .theme)|$n|$(sed -n '1s/^# *//p' "$f")"
  done
}

FONT_PREVIEW_PID=''
preview_fonts() {
  # Only when the font menu will really be asked (not on --update or unattended runs).
  if _isset TUX_FONT || [[ -n ${TUX_YES:-} ]]; then return 0; fi
  # Real previews need a graphical session; on a bare TTY we can only describe them.
  local img="$TUX_SRC/assets/font-previews/all.png"
  [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} && -f $img ]] || {
    info "Font previews: open $TUX_SRC/assets/font-previews/all.png, or run 'tux-font' after install for live previews."
    return 0
  }
  local v
  for v in imv feh xdg-open; do
    if command -v "$v" >/dev/null; then
      runuser -u "${SUDO_USER:-root}" -- "$v" "$img" >/dev/null 2>&1 &
      FONT_PREVIEW_PID=$!
      trap close_font_preview EXIT   # also close it if the install stops early
      return 0
    fi
  done
}

# Close the preview window once a font is picked (runuser passes the signal on to the viewer).
close_font_preview() {
  [[ -n $FONT_PREVIEW_PID ]] || return 0
  kill "$FONT_PREVIEW_PID" 2>/dev/null || true
  FONT_PREVIEW_PID=''
}

# Already set up here (answers saved by an earlier run): offer to keep them instead of asking again.
offer_update() {
  local saved=$TUX_ETC/answers.conf
  [[ -z $CONFIG && -z ${TUX_MODE:-} && -r $saved ]] || return 0
  ((IS_LIVE)) && ((!FORCE_DESKTOP)) && return 0
  if ((UPDATE)); then TUX_HOW=update
  else
    choose TUX_HOW "tuxcraft is already set up here (choices saved $(date -r "$saved" +%F)). What now?" update \
      "update|Update|keep every choice: new tools, configs and fixes only" \
      "extras|Update + change extras|keep your choices, re-pick the optional extras (music, printing, ...)" \
      "redo|Answer everything again|your files and settings stay"
  fi
  [[ $TUX_HOW == redo ]] && return 0
  # shellcheck source=/dev/null
  . "$saved"
  TUX_MODE=desktop TUX_UPDATE=1
  export TUX_UPDATE
  # The theme may have changed since (tux-theme): the user's state file is the truth.
  local home st
  home=$(getent passwd "$TUX_USER" | cut -d: -f6); st="$home/.config/tuxcraft/state"
  [[ -r $st ]] && TUX_THEME=$(sed -n 's/^THEME=//p' "$st" | tr -d "\"'")
  if [[ $TUX_HOW == extras ]]; then
    TUX_SAVED_BUNDLES=${TUX_BUNDLES:-}; unset TUX_BUNDLES
  fi
  return 0
}

# Default for an extra in the checklist: the saved choice when re-picking, else the stock default.
# Something installed by hand since counts as chosen (e.g. cups for printing).
extra_default() {  # extra_default key stock
  [[ -v TUX_SAVED_BUNDLES ]] || { echo "$2"; return; }
  local cmd=''
  case $1 in
    music) cmd=mpd ;; printing) cmd=lpadmin ;; office) cmd=soffice ;; flatpak) cmd=flatpak ;;
    dev) cmd=docker ;; gaming) cmd=steam ;; bluetooth) cmd=bluetoothctl ;; firewall) cmd=nft ;;
  esac
  if has_word "$TUX_SAVED_BUNDLES" "$1" || { [[ -n $cmd ]] && command -v "$cmd" >/dev/null; }; then echo on; else echo off; fi
}

wizard() {
  clear || true
  banner
  info "Detected: $DISTRO_ID, ${BOOT_MODE^^} boot, GPU: ${GPU_VENDORS:-none}$( ((IS_LAPTOP)) && echo ', laptop')"
  offer_update

  if [[ -z ${TUX_MODE:-} ]]; then
    if ((IS_TUXISO)) && ((!FORCE_DESKTOP)); then
      TUX_MODE=install
    elif ((IS_LIVE)) && ((!FORCE_DESKTOP)); then
      choose TUX_MODE "You are on a live system. What should tuxcraft do?" install \
        "install|Install to a disk|$(installable_distros | sed 's/ /, /g') + desktop" \
        "desktop|Set up this system|only if this is NOT the live ISO"
    else
      TUX_MODE=desktop
    fi
  fi

  if [[ $TUX_MODE == install ]]; then
    local -a dopts=() d
    for d in $(installable_distros); do
      case $d in
        arch)   dopts+=("arch|Arch Linux|rolling, newest everything, AUR") ;;
        debian) dopts+=("debian|Debian ${TUX_DEBIAN_SUITE:-13 (trixie)}|stable, changes slowly") ;;
        void)   dopts+=("void|Void Linux|rolling, runit instead of systemd, very light") ;;
      esac
    done
    choose TUX_DISTRO "Which Linux should tuxcraft install?" "$HOST_DISTRO" "${dopts[@]}"
    has_word "$(installable_distros)" "$TUX_DISTRO" || die "This live system cannot install '$TUX_DISTRO' (it can: $(installable_distros)). The tuxcraft ISO installs all three."
    DISTRO=$TUX_DISTRO
    pick_target
    pick_encryption
    ask TUX_HOSTNAME "Computer name" tuxbox
    ask TUX_USER "Your username" "${SUDO_USER:-user}"
    [[ $TUX_USER =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid username '$TUX_USER'"
    if [[ -z ${TUX_PASSWORD:-} ]]; then
      [[ -n ${TUX_YES:-} ]] && die "TUX_PASSWORD must be set for unattended installs"
      ask_secret TUX_PASSWORD "Password for $TUX_USER (also used for sudo)"
    fi
    if [[ -z ${TUX_TIMEZONE:-} ]]; then
      if [[ -z ${TUX_GEOIP:-} && -z ${TUX_YES:-} ]]; then
        confirm "Detect your timezone online? (sends your IP address to ipapi.co)" n && TUX_GEOIP=yes || TUX_GEOIP=no
      fi
      ask TUX_TIMEZONE "Timezone (Region/City, e.g. Asia/Kolkata)" "$(guess_timezone)"
    fi
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
  close_font_preview
  ask TUX_FONT_SIZE "UI font size" 11

  choose TUX_BROWSER "Web browser" firefox \
    "firefox|Firefox|" "chromium|Chromium|" "none|None|install your own later"
  [[ $TUX_BROWSER == none ]] || TUX_BUNDLES_BROWSER=$TUX_BROWSER

  local bt=off aur=off prn="CUPS, finds network/USB printers by itself"
  ((HAS_BT)) && bt=on
  [[ -n ${PRINTERS:-} ]] && prn="found: $PRINTERS"
  [[ $DISTRO == arch ]] && aur=on
  checklist TUX_BUNDLES "Optional extras" \
    "firewall|Firewall (nftables)|$(extra_default firewall on)|block incoming connections; SSH open to the LAN only" \
    "flatpak|Flatpak + Flathub|$(extra_default flatpak on)|sandboxed apps, themed like the rest" \
    "wallpapers|debi3n wallpapers|$(extra_default wallpapers on)|~320 MB pack from plaintextlab/debi3n" \
    "bluetooth|Bluetooth|$(extra_default bluetooth $bt)|bluez + bluetui" \
    "music|Music|$(extra_default music on)|rmpc + mpd: album art, cava visualizer; folder via tux-music" \
    "printing|Printing|$(extra_default printing on)|$prn" \
    "dev|Developer tools|$(extra_default dev off)|docker, lazydocker, node, go, rust, python" \
    "office|Office & PDF|$(extra_default office on)|LibreOffice + zathura" \
    "gaming|Gaming|$(extra_default gaming off)|Steam, gamemode, MangoHud (+ 32-bit drivers)" \
    "aur|AUR helper (paru)|$(extra_default aur $aur)|Arch only"
  # A reused answers file already lists the browser; don't add it twice.
  [[ -n ${TUX_BUNDLES_BROWSER:-} ]] && ! has_word "${TUX_BUNDLES:-}" "$TUX_BUNDLES_BROWSER" && TUX_BUNDLES+=" $TUX_BUNDLES_BROWSER"

  if [[ -z ${TUX_YES:-} ]]; then
    [[ -v TUX_EXTRA ]] || read -r -e -p "${C_BOLD}? Extra packages to install${C_RESET} ${C_DIM}(space separated, Enter for none)${C_RESET} " TUX_EXTRA </dev/tty
    [[ -v TUX_EXCLUDE ]] || read -r -e -p "${C_BOLD}? Packages to leave out${C_RESET} ${C_DIM}(e.g. picom copyq, Enter for none)${C_RESET} " TUX_EXCLUDE </dev/tty
  fi
  TUX_EXTRA=${TUX_EXTRA:-} TUX_EXCLUDE=${TUX_EXCLUDE:-}

  printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-12s %s\n' Mode "$TUX_MODE${TUX_UPDATE:+ (update, saved choices)}" Distro "$DISTRO" User "$TUX_USER" Session "$TUX_SESSION" \
    NVIDIA "$TUX_NVIDIA" Theme "$TUX_THEME" Font "$(font_field "$TUX_FONT" 2) $TUX_FONT_SIZE" \
    Browser "$TUX_BROWSER" Extras "${TUX_BUNDLES:-none}"
  [[ $TUX_MODE == install ]] && printf '  %-12s %s\n' Disk "$(target_summary), btrfs + snapshots" \
    Encryption "$([[ ${TUX_ENCRYPT:-no} == yes ]] && echo 'LUKS2 (passphrase at power-on)' || echo none)" Host "$TUX_HOSTNAME" \
    Timezone "$TUX_TIMEZONE" Locale "$TUX_LOCALE" Keyboard "$TUX_KEYMAP"
  [[ -n $TUX_EXTRA ]] && printf '  %-12s %s\n' "+ packages" "$TUX_EXTRA"
  [[ -n $TUX_EXCLUDE ]] && printf '  %-12s %s\n' "- packages" "$TUX_EXCLUDE"
  echo
  confirm "Start?" y || die "Aborted, nothing was changed."
  [[ $TUX_MODE == install ]] && confirm_wipe
  return 0
}

# Runs on the final system: inside the chroot for fresh installs, directly otherwise.
# The password reaches the chroot through a root-only file on the new system's /run, a tmpfs:
# never on its disk, and not in the environment (/proc/*/environ) of every process in the chroot.
TUX_SECRET=/run/tuxcraft/secret
read_secret() {
  [[ -r $TUX_SECRET ]] || return 0
  TUX_PASSWORD=$(<"$TUX_SECRET")
  rm -f "$TUX_SECRET"
}

# TUX_POST_HOOK: your own script, run as root at the very end inside the new system.
run_post_hook() {
  local h=$TUX_ETC/post-hook
  [[ -f $h ]] || return 0
  step "Running your post-install hook"
  run bash "$h" || warn "Post-install hook failed (see $TUX_LOG)"
}

target_stage() {
  export TUX_USER
  if [[ $TUX_MODE == install ]]; then
    system_stage
  else
    pkg_refresh
    sys_pkgmanager
  fi
  sys_writeback
  # Only now: on a fresh install the user is created by system_stage.
  TUX_HOME=$(getent passwd "$TUX_USER" | cut -d: -f6)
  export TUX_HOME
  gpu_stage
  desktop_stage
  hwfix_stage
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
  run_post_hook
}

main() {
  detect_all
  if [[ $STAGE == target ]]; then
    # shellcheck source=/dev/null
    . "$TUX_ETC/answers.conf"
    read_secret
    target_stage
    exit 0
  fi

  wizard
  local start=$SECONDS
  if [[ $TUX_MODE == install ]]; then
    live_prereqs   # partitioning needs parted and dosfstools, which the Debian live ISO lacks
    disk_prepare
    bootstrap_base
    step "Handing over to the new system"
    mkdir -p "$TARGET$TUX_SHARE" "$TARGET$TUX_ETC"
    cp -a "$TUX_SRC"/. "$TARGET$TUX_SHARE"/
    save_answers "$TARGET$TUX_ETC/answers.conf"
    if [[ -n ${TUX_POST_HOOK:-} ]]; then
      [[ -f $TUX_POST_HOOK ]] || die "TUX_POST_HOOK: $TUX_POST_HOOK not found"
      install -m700 "$TUX_POST_HOOK" "$TARGET$TUX_ETC/post-hook"
    fi
    mountpoint -q "$TARGET/run" || mount -t tmpfs tmpfs "$TARGET/run"
    (umask 077; mkdir -p "$TARGET${TUX_SECRET%/*}"; printf '%s' "$TUX_PASSWORD" >"$TARGET$TUX_SECRET")
    chroot "$TARGET" /usr/bin/env TUX_LOG=/var/log/tuxcraft.log \
      TUX_YES="${TUX_YES:-}" bash "$TUX_SHARE/install.sh" --stage target || die "Setup inside the new system failed. Log: $TARGET/var/log/tuxcraft.log"
    rm -f "$TARGET$TUX_SECRET"
    cat "$TUX_LOG" >>"$TARGET/var/log/tuxcraft-live.log" 2>/dev/null || true
    target_release
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
    ((NO_REBOOT)) || { confirm "Reboot now?" y && reboot; }
  else
    info "Log out and back in (or reboot) to start the new session."
  fi
}

main
