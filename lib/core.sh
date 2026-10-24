# shellcheck shell=bash
# Environment detection and small helpers shared by every stage.

TUX_SHARE=/usr/share/tuxcraft
TUX_ETC=/etc/tuxcraft

detect_distro() {
  local id='' like=''
  # shellcheck disable=SC1091
  [[ -r /etc/os-release ]] && { id=$(. /etc/os-release; echo "${ID:-}"); like=$(. /etc/os-release; echo "${ID_LIKE:-}"); }
  case " $id $like " in
    *" arch "*|*" archlinux "*) DISTRO=arch ;;
    *" void "*)                 DISTRO=void ;;
    *" debian "*|*" ubuntu "*)  DISTRO=debian ;;
    *) die "Unsupported distribution '$id'. Supported: Arch, Debian, Void (and close derivatives)." ;;
  esac
  [[ $id == ubuntu || $like == *ubuntu* ]] && warn "Ubuntu-based systems are treated as Debian; package names may differ."
  DISTRO_ID=$id
}

# A live ISO runs from an overlay/squashfs root. An installed system does not.
detect_live() {
  local fstype
  fstype=$(findmnt -no FSTYPE / 2>/dev/null || true)
  if [[ -d /run/archiso || -d /run/live/medium || -d /run/initramfs/live ]] || [[ $fstype =~ ^(overlay|tmpfs|squashfs|rootfs|airootfs)$ ]]; then
    IS_LIVE=1
  else
    IS_LIVE=0
  fi
}

detect_firmware() { [[ -d /sys/firmware/efi/efivars ]] && BOOT_MODE=uefi || BOOT_MODE=bios; }

detect_cpu() {
  if grep -q GenuineIntel /proc/cpuinfo; then CPU_VENDOR=intel
  elif grep -q AuthenticAMD /proc/cpuinfo; then CPU_VENDOR=amd
  else CPU_VENDOR=other; fi
}

# Reads /sys directly so it works before pciutils is installed.
detect_gpu() {
  local d vendor
  GPU_VENDORS=''
  for d in /sys/bus/pci/devices/*; do
    [[ -r $d/class ]] || continue
    [[ $(<"$d/class") == 0x03* ]] || continue        # display controllers only
    vendor=$(<"$d/vendor")
    case $vendor in
      0x10de) has_word "$GPU_VENDORS" nvidia || GPU_VENDORS+=' nvidia' ;;
      0x1002) has_word "$GPU_VENDORS" amd    || GPU_VENDORS+=' amd' ;;
      0x8086) has_word "$GPU_VENDORS" intel  || GPU_VENDORS+=' intel' ;;
      0x15ad|0x1af4|0x1234|0x80ee) has_word "$GPU_VENDORS" vm || GPU_VENDORS+=' vm' ;;
    esac
  done
  GPU_VENDORS=${GPU_VENDORS# }
  # NVIDIA generation: Turing (TU) and newer use the open kernel modules.
  NVIDIA_GEN=''
  if has_word "$GPU_VENDORS" nvidia && command -v lspci >/dev/null; then
    if lspci -nn | grep -iE 'vga|3d|display' | grep -i nvidia | grep -qE '\b(TU|GA|GH|AD|GB)[0-9]{3}'; then
      NVIDIA_GEN=modern
    else
      NVIDIA_GEN=legacy
    fi
  elif has_word "$GPU_VENDORS" nvidia; then
    NVIDIA_GEN=modern
  fi
}

detect_laptop() { compgen -G '/sys/class/power_supply/BAT*' >/dev/null && IS_LAPTOP=1 || IS_LAPTOP=0; }
detect_bluetooth() { compgen -G '/sys/class/bluetooth/*' >/dev/null && HAS_BT=1 || HAS_BT=0; }

detect_all() {
  detect_distro; detect_live; detect_firmware; detect_cpu; detect_gpu; detect_laptop; detect_bluetooth
  if [[ -d /run/systemd/system ]] || [[ $DISTRO != void ]]; then INIT=systemd; else INIT=runit; fi
}

# ---------------------------------------------------------------- services
svc_enable() {
  local s
  for s in "$@"; do
    if [[ $INIT == systemd ]]; then
      systemctl enable "$s" >>"$TUX_LOG" 2>&1 || warn "Could not enable $s"
    else
      if [[ -d /etc/sv/$s ]]; then
        ln -sfn "/etc/sv/$s" "/etc/runit/runsvdir/default/$s"
      else
        warn "runit service $s not found"
      fi
    fi
  done
}

svc_disable() {
  local s
  for s in "$@"; do
    if [[ $INIT == systemd ]]; then
      systemctl disable "$s" >>"$TUX_LOG" 2>&1 || true
    else
      rm -f "/etc/runit/runsvdir/default/$s"
    fi
  done
}

# ---------------------------------------------------------------- helpers
run() { _log "RUN   $*"; "$@" >>"$TUX_LOG" 2>&1; }

# as_user cmd... : run as the desktop user with a sane environment
as_user() {
  runuser -u "$TUX_USER" -- env HOME="$TUX_HOME" USER="$TUX_USER" LOGNAME="$TUX_USER" \
    PATH="/usr/local/bin:/usr/bin:/bin" TUX_NO_RELOAD=1 "$@"
}

fetch() { curl -fL --retry 3 --connect-timeout 15 -o "$2" "$1" >>"$TUX_LOG" 2>&1; }

# gh_latest_tag owner/repo -> v1.2.3 (follows the /releases/latest redirect, no API token needed)
gh_latest_tag() {
  curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's#.*/tag/##'
}

write_file() {  # write_file path mode <<content
  install -Dm"${2:-644}" /dev/stdin "$1"
}
