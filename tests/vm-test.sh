#!/usr/bin/env bash
# vm-test.sh — install tuxcraft into a throwaway QEMU VM, from THIS working tree.
#
#   tests/vm-test.sh arch                      UEFI, i3, gruvbox
#   tests/vm-test.sh debian --bios --session sway
#   tests/vm-test.sh void --theme nord --font dos
#   tests/vm-test.sh arch --boot               boot the installed disk again (no ISO)
#   tests/vm-test.sh arch --reset              delete that VM's disk and start over
#
# How a run goes:
#   1. Downloads + checksum-verifies the distro's live ISO (cached in tests/.vm/iso/).
#   2. Serves this checkout over HTTP on the host (guest sees it at 10.0.2.2:8000).
#   3. Boots the ISO. You type ONE line in the VM console (printed below), the install runs
#      unattended from a generated answers file (disk /dev/vda, user tux / password tux).
#   4. The VM reboots into the installed system. Log in as tux, then run the checker:
#        curl -fsSL 10.0.2.2:8000/check | bash
#      It prints PASS/WARN/FAIL for every part of the setup and exits non-zero on failure.
#
# Host needs: qemu-system-x86_64, qemu-img, python3, curl; OVMF/edk2 for UEFI; /dev/kvm.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
VMROOT="$HERE/.vm"
PORT=${PORT:-8000}

DISTRO='' FW=uefi SESSION=i3 THEME=gruvbox FONT=jetbrains MODE=install
RAM=${RAM:-4096} CPUS=${CPUS:-4} DISK_SIZE=${DISK_SIZE:-30G} GL=0 DISPLAY_OPT=''
usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; cat <<'EOF'
Options:
  --bios | --uefi        firmware (default uefi)
  --session i3|sway      default i3
  --theme NAME           default gruvbox
  --font KEY             default jetbrains
  --boot                 boot the installed disk, skip the ISO
  --reset                delete this VM and exit
  --gl                   3D-accelerated virtio GPU (virgl). Smoother sway, but on many
                         hosts (NVIDIA especially) the QEMU window stays black
  --no-gl                plain virtio-vga (the default)
  --vnc                  no local window; VNC on :1 (port 5901)
Env: RAM (MiB, 4096) CPUS (4) DISK_SIZE (30G) PORT (8000)
EOF
}

while (($#)); do
  case $1 in
    arch|debian|void) DISTRO=$1 ;;
    --bios) FW=bios ;; --uefi) FW=uefi ;;
    --session) SESSION=$2; shift ;;
    --theme) THEME=$2; shift ;;
    --font) FONT=$2; shift ;;
    --boot) MODE=boot ;;
    --reset) MODE=reset ;;
    --no-gl) GL=0 ;;
    --gl) GL=1 ;;
    --vnc) DISPLAY_OPT=vnc ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done
[[ -n $DISTRO ]] || { usage; exit 1; }
[[ $SESSION == i3 || $SESSION == sway ]] || { echo "--session must be i3 or sway" >&2; exit 1; }
[[ -f $REPO/themes/$THEME.theme ]] || { echo "Unknown theme $THEME" >&2; exit 1; }

VM="$VMROOT/$DISTRO-$FW"
DISK="$VM/disk.qcow2"
mkdir -p "$VM" "$VMROOT/iso"

if [[ $MODE == reset ]]; then rm -rf "$VM"; echo "Removed $VM"; exit 0; fi

for t in qemu-system-x86_64 qemu-img python3 curl; do
  command -v "$t" >/dev/null || { echo "Missing host tool: $t" >&2; exit 1; }
done
KVM=()
if [[ -w /dev/kvm ]]; then KVM=(-enable-kvm -cpu host)
else echo "!! /dev/kvm not usable: the VM will be very slow (add yourself to the kvm group)"; KVM=(-cpu max); fi

# ------------------------------------------------------------------ ISO
# Resolves the current release name from the distro's checksum file, so no URL goes stale.
iso_info() {  # -> "url sha256"
  local base sums line
  case $DISTRO in
    arch)
      base=https://geo.mirror.pkgbuild.com/iso/latest
      sums=$(curl -fsSL "$base/sha256sums.txt")
      line=$(grep -E '  archlinux-[0-9.]+-x86_64\.iso$' <<<"$sums" | head -n1)
      echo "$base/${line##* } ${line%% *}" ;;
    debian)
      base=https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid
      sums=$(curl -fsSL "$base/SHA256SUMS")
      line=$(grep -E 'debian-live-[0-9.]+-amd64-standard\.iso$' <<<"$sums" | head -n1)
      echo "$base/${line##* } ${line%% *}" ;;
    void)
      base=https://repo-default.voidlinux.org/live/current
      sums=$(curl -fsSL "$base/sha256sum.txt")
      # format: SHA256 (void-live-x86_64-YYYYMMDD-base.iso) = <hash>
      line=$(grep -E '\(void-live-x86_64-[0-9]+-base\.iso\)' <<<"$sums" | head -n1)
      local name=${line#*(}; name=${name%%)*}
      echo "$base/$name ${line##* }" ;;
  esac
}

ISO=''
if [[ $MODE == install ]]; then
  read -r url sum < <(iso_info) || true
  [[ -n ${url:-} && -n ${sum:-} ]] || { echo "Could not find the current $DISTRO ISO" >&2; exit 1; }
  ISO="$VMROOT/iso/${url##*/}"
  if [[ ! -f $ISO ]]; then
    echo ":: Downloading ${url##*/}"
    curl -fL --retry 3 -o "$ISO.part" "$url"
    mv "$ISO.part" "$ISO"
  fi
  echo ":: Verifying checksum"
  echo "$sum  $ISO" | sha256sum -c --quiet - || { rm -f "$ISO"; echo "Checksum mismatch, ISO deleted. Run again." >&2; exit 1; }
fi

# ------------------------------------------------------------------ disk + firmware
[[ -f $DISK ]] || qemu-img create -q -f qcow2 "$DISK" "$DISK_SIZE"
if [[ $MODE == boot && ! -f $VM/installed ]]; then
  echo "Nothing installed on $DISK yet; run without --boot first." >&2; exit 1
fi

FW_ARGS=()
if [[ $FW == uefi ]]; then
  code='' vars=''
  for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/edk2/ovmf/OVMF_CODE.fd \
           /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.fd /usr/share/qemu/edk2-x86_64-code.fd; do
    [[ -f $c ]] && { code=$c; break; }
  done
  [[ -n $code ]] || { echo "UEFI firmware (OVMF/edk2) not found. Install edk2-ovmf / ovmf, or use --bios." >&2; exit 1; }
  for v in "${code/CODE/VARS}" /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/qemu/edk2-i386-vars.fd; do
    [[ -f $v ]] && { vars=$v; break; }
  done
  [[ -f $VM/OVMF_VARS.fd ]] || cp "$vars" "$VM/OVMF_VARS.fd"
  FW_ARGS=(-drive "if=pflash,format=raw,readonly=on,file=$code" -drive "if=pflash,format=raw,file=$VM/OVMF_VARS.fd")
fi

# ------------------------------------------------------------------ HTTP payload
SERVE="$VM/serve"
rm -rf "$SERVE"; mkdir -p "$SERVE"
tar -C "$REPO" --exclude=.git --exclude=tests/.vm -czf "$SERVE/tuxcraft.tar.gz" .
cp "$HERE/vm-check.sh" "$SERVE/check"
cat >"$SERVE/answers.conf" <<EOF
# Generated by tests/vm-test.sh — unattended test install
TUX_MODE=install
TUX_DISK=/dev/vda
TUX_WIPE_CONFIRMED=1
TUX_HOSTNAME=tux-$DISTRO
TUX_USER=tux
TUX_PASSWORD=tux
TUX_TIMEZONE=UTC
TUX_LOCALE=en_US.UTF-8
TUX_KEYMAP=us
TUX_SESSION=$SESSION
TUX_NVIDIA=no
TUX_THEME=$THEME
TUX_FONT=$FONT
TUX_FONT_SIZE=11
TUX_BROWSER=none
TUX_BUNDLES="gui-fm flatpak bluetooth"
TUX_EXTRA=""
TUX_EXCLUDE=""
EOF
cat >"$SERVE/go" <<EOF
#!/bin/sh
# Typed into the live VM: fetch this checkout from the host and run it unattended.
set -e
get() { curl -fsSL "http://10.0.2.2:$PORT/\$1" -o "\$2" 2>/dev/null || wget -qO "\$2" "http://10.0.2.2:$PORT/\$1"; }
rm -rf /tmp/tuxcraft && mkdir -p /tmp/tuxcraft
get tuxcraft.tar.gz /tmp/tuxcraft.tar.gz
get answers.conf /tmp/answers.conf
tar -xzf /tmp/tuxcraft.tar.gz -C /tmp/tuxcraft
exec bash /tmp/tuxcraft/install.sh --config /tmp/answers.conf --yes </dev/tty
EOF

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SERVE" >"$VM/http.log" 2>&1 &
HTTP_PID=$!
trap 'kill $HTTP_PID 2>/dev/null' EXIT
sleep 0.5
kill -0 $HTTP_PID 2>/dev/null || { echo "Could not start HTTP server on port $PORT (busy? set PORT=)" >&2; exit 1; }

# ------------------------------------------------------------------ boot
DEV=(-drive "file=$DISK,if=none,id=d0,format=qcow2,discard=unmap" -device "virtio-blk-pci,drive=d0,bootindex=1")
# CD only during installs; bootindex 2 means "try the empty disk first, fall back to the CD",
# so the automatic reboot at the end lands in the installed system.
[[ -n $ISO ]] && DEV+=(-drive "file=$ISO,media=cdrom,if=none,id=cd0,readonly=on" -device "ide-cd,drive=cd0,bootindex=2")

if [[ $DISPLAY_OPT == vnc ]]; then
  VIDEO=(-device virtio-vga -display none -vnc 127.0.0.1:1)
elif ((GL)); then
  VIDEO=(-device virtio-vga-gl -display "gtk,gl=on")
else
  VIDEO=(-device virtio-vga -display gtk)
fi

cat <<EOF

────────────────────────────────────────────────────────────────────────
 $DISTRO / $FW / $SESSION / $THEME / $FONT     disk: $DISK
EOF
if [[ $MODE == install ]]; then
  case $DISTRO in
    arch)   cmd="curl -fsSL 10.0.2.2:$PORT/go | sh" ; login="(already root)" ;;
    debian) cmd="curl -fsSL 10.0.2.2:$PORT/go | sudo sh   (or: wget -qO- 10.0.2.2:$PORT/go | sudo sh)"; login="(auto-login as user)" ;;
    void)   cmd="curl -fsSL 10.0.2.2:$PORT/go | sh" ; login="log in as root / voidlinux" ;;
  esac
  cat <<EOF
 1. When the live system is up $login, type:
      $cmd
 2. It installs unattended and reboots into the new system.
 3. Log in as tux / tux, open a terminal (Super+Enter) and run:
      curl -fsSL 10.0.2.2:$PORT/check | bash
EOF
else
  cat <<EOF
 Log in as tux / tux, then: curl -fsSL 10.0.2.2:$PORT/check | bash
EOF
fi
[[ $DISPLAY_OPT == vnc ]] && echo " Display: VNC on 127.0.0.1:5901"
echo "────────────────────────────────────────────────────────────────────────"

[[ $MODE == install ]] && touch "$VM/installed"
qemu-system-x86_64 "${KVM[@]}" -machine q35 -m "$RAM" -smp "$CPUS" -name "tuxcraft-$DISTRO" \
  "${FW_ARGS[@]}" "${DEV[@]}" \
  -nic user,model=virtio-net-pci \
  -device qemu-xhci -device usb-tablet \
  "${VIDEO[@]}"
