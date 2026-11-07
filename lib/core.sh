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
  # The system tuxcraft runs on. During a fresh install DISTRO becomes the one being installed
  # (TUX_DISTRO), which can differ: the tuxcraft ISO is Arch-based and installs all three.
  HOST_DISTRO=$DISTRO
  [[ -f /etc/tuxcraft-iso ]] && IS_TUXISO=1 || IS_TUXISO=0
}

# Distros a fresh install can produce from this host. The first step of an install (base system
# into /mnt) needs the target's bootstrap tool on the host: pacstrap only exists on Arch, while
# debootstrap and a static xbps run anywhere.
installable_distros() {
  case $HOST_DISTRO in
    arch)   echo arch debian void ;;
    debian) echo debian void ;;
    void)   echo void debian ;;
  esac
}

# A live ISO runs from an overlay/squashfs root. An installed system does not.
detect_live() {
  local fstype
  fstype=$(findmnt -no FSTYPE / 2>/dev/null || true)
  if [[ -f /etc/tuxcraft-iso || -d /run/archiso || -d /run/live/medium || -d /run/initramfs/live ]] || [[ $fstype =~ ^(overlay|tmpfs|squashfs|rootfs|airootfs)$ ]]; then
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
    if lspci -nn | grep -iE 'vga|3d|display' | grep -i nvidia | grep -E '\b(TU|GA|GH|AD|GB)[0-9]{3}' >/dev/null; then
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

# Printers: USB ones (interface class 07) and, when an mDNS browser is available, network ones.
# Sets PRINTERS ("make model, ..." for the wizard) and PRINTER_MAKES (hp epson brother samsung canon).
printer_make() {
  case ${1,,} in
    *hewlett*|hp*|*" hp "*|03f0) echo hp ;; *epson*|04b8) echo epson ;; *brother*|04f9) echo brother ;;
    *samsung*|04e8) echo samsung ;; *canon*|04a9) echo canon ;;
  esac
}
detect_printers() {
  PRINTERS='' PRINTER_MAKES=''
  local d m name
  for d in /sys/bus/usb/devices/*:*; do
    [[ $(cat "$d/bInterfaceClass" 2>/dev/null) == 07 ]] || continue
    d=${d%:*}
    name="$(cat "$d/manufacturer" 2>/dev/null) $(cat "$d/product" 2>/dev/null)"
    m=$(printer_make "$(cat "$d/idVendor" 2>/dev/null)")
    PRINTERS+="${PRINTERS:+, }${name# } (USB)"; [[ -n $m ]] && PRINTER_MAKES+=" $m"
  done
  if command -v avahi-browse >/dev/null; then
    while IFS= read -r name; do
      PRINTERS+="${PRINTERS:+, }$name (network)"
      m=$(printer_make "$name"); [[ -n $m ]] && PRINTER_MAKES+=" $m"
    done < <(timeout 5 avahi-browse -tpk _ipp._tcp 2>/dev/null | awk -F';' '$1=="+" {print $4}' | sed 's/\\032/ /g' | sort -u)
  fi
  PRINTER_MAKES=$(tr ' ' '\n' <<<"$PRINTER_MAKES" | sed '/^$/d' | sort -u | tr '\n' ' ')
  return 0
}

detect_all() {
  detect_distro; detect_live; detect_firmware; detect_cpu; detect_gpu; detect_laptop; detect_bluetooth; detect_printers
  set_init
}

set_init() { if [[ -d /run/systemd/system ]] || [[ $DISTRO != void ]]; then INIT=systemd; else INIT=runit; fi; }

# ---------------------------------------------------------------- services
svc_enable() {
  local s
  for s in "$@"; do
    if [[ $INIT == systemd ]]; then
      run systemctl enable "$s" || warn "Could not enable $s"
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
      run systemctl disable "$s" || true
    else
      rm -f "/etc/runit/runsvdir/default/$s"
    fi
  done
}

# ---------------------------------------------------------------- helpers
# run cmd... : show the command on screen ("$ cmd"), stream its output below it (dimmed,
# indented) and keep all of it in the log. TUX_QUIET=1 hides the output; the log still has it.
run() {
  local rc=0 fd pid i
  TUX_LAST_RUN="$*"; _log "RUN   $*"
  printf '%s  $ %s%s\n' "$C_DIM" "$*" "$C_RESET"
  exec {fd}> >(_show_output); pid=$!
  "$@" >&"$fd" 2>&1 || rc=$?
  exec {fd}>&-
  # Let the last lines reach the screen before anything else prints. Capped: a daemon the
  # command started (gpg-agent, say) can keep the output open, and the install must go on.
  for ((i = 0; i < 40; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
  return "$rc"
}

# Copies a command's output into the log and, unless TUX_QUIET is set, onto the screen.
_show_output() {
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    printf '%s\n' "$line" >>"$TUX_LOG" 2>/dev/null
    [[ -n ${TUX_QUIET:-} ]] && continue
    line=${line##*$'\r'}   # progress bars redraw with \r: show only their last state
    printf '%s    %s%s\n' "$C_DIM" "$line" "$C_RESET"
  done
}

# as_user cmd... : run as the desktop user with a sane environment
as_user() {
  runuser -u "$TUX_USER" -- env HOME="$TUX_HOME" USER="$TUX_USER" LOGNAME="$TUX_USER" \
    PATH="/usr/local/bin:/usr/bin:/bin" TUX_NO_RELOAD=1 "$@"
}

fetch() { run curl -fL --retry 3 --connect-timeout 15 --no-progress-meter -o "$2" "$1"; }

write_file() {  # write_file path mode <<content
  install -Dm"${2:-644}" /dev/stdin "$1"
}
