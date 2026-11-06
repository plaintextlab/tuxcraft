#!/usr/bin/env bash
# ci-vm.sh — fully unattended end-to-end test: install from the tuxcraft ISO into a QEMU VM,
# boot the result, run tests/vm-check.sh inside it, and exit with its verdict.
#
#   tests/ci-vm.sh ISO DISTRO [--session i3|sway] [--luks] [--bios] [--target disk|free]
#
# No keystrokes are needed for the install: a second virtual disk labelled TUXCFG carries
# answers.conf, a post-install hook and a report URL (see iso/airootfs/usr/local/bin/tuxcraft-live).
# The hook adds a first-boot service to the new system that runs vm-check and uploads the result.
# With --luks the passphrase is typed into GRUB through the QEMU monitor (the only key presses).
#
# Host needs: qemu-system-x86_64, qemu-img, python3, mtools + dosfstools, OVMF (UEFI), /dev/kvm.
# Env: RAM (4096) CPUS (4) PORT (8000) TIMEOUT_INSTALL (5400 s) TIMEOUT_BOOT (900 s)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ISO=${1:?usage: ci-vm.sh ISO DISTRO [options]}; DISTRO=${2:?distro}; shift 2
SESSION=i3 LUKS=0 FW=uefi TARGET_MODE=disk
while (($#)); do
  case $1 in
    --session) SESSION=$2; shift ;;
    --luks) LUKS=1 ;;
    --bios) FW=bios ;;
    --target) TARGET_MODE=$2; shift ;;
    *) echo "Unknown argument $1" >&2; exit 1 ;;
  esac
  shift
done
RAM=${RAM:-4096} CPUS=${CPUS:-4} PORT=${PORT:-8000}
TIMEOUT_INSTALL=${TIMEOUT_INSTALL:-5400} TIMEOUT_BOOT=${TIMEOUT_BOOT:-900}
LUKS_PASS=tuxlukspw   # no "c" or "e": typed into GRUB, where those keys open the console/editor

W=$(mktemp -d /tmp/tuxcraft-ci.XXXXXX)
SERVE=$W/serve; mkdir -p "$SERVE/up"
DISK=$W/disk.qcow2 CFG=$W/tuxcfg.img MON=$W/monitor.sock
echo ":: work dir $W  ($DISTRO / $FW / $SESSION / luks=$LUKS / target=$TARGET_MODE)"

KVM=(-cpu max)
[[ -w /dev/kvm ]] && KVM=(-enable-kvm -cpu host) || echo "!! no /dev/kvm: this will be very slow"

FW_ARGS=()
if [[ $FW == uefi ]]; then
  code='' vars=''
  for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd \
           /usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/qemu/edk2-x86_64-code.fd; do [[ -f $c ]] && { code=$c; break; }; done
  for v in "${code/CODE/VARS}" /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd; do
    [[ -f $v ]] && { vars=$v; break; }; done
  [[ -n $code && -n $vars ]] || { echo "OVMF not found" >&2; exit 1; }
  cp "$vars" "$W/vars.fd"
  FW_ARGS=(-drive "if=pflash,format=raw,readonly=on,file=$code" -drive "if=pflash,format=raw,file=$W/vars.fd")
fi

# ------------------------------------------------------------------ disk
qemu-img create -q -f qcow2 "$DISK" 40G
if [[ $TARGET_MODE == free ]]; then
  # Simulate a dual-boot disk: an ESP and a 10 GiB "other OS" partition, the rest left free.
  raw=$W/pre.raw; truncate -s 40G "$raw"
  printf 'label: gpt\nstart=2048, size=300MiB, type=U, name="EFI"\nsize=10GiB, type=L, name="other"\n' | sfdisk -q "$raw"
  # A real (empty) FAT32 ESP at sector 2048, as Windows would leave it.
  mkfs.vfat -F 32 -n EFI --offset 2048 "$raw" $((300 * 1024)) >/dev/null
  qemu-img convert -q -f raw -O qcow2 "$raw" "$DISK"; rm -f "$raw"
fi

# ------------------------------------------------------------------ TUXCFG
cp "$HERE/vm-check.sh" "$SERVE/check"
cat >"$W/answers.conf" <<EOF
TUX_MODE=install
TUX_DISTRO=$DISTRO
TUX_TARGET=$TARGET_MODE
TUX_DISK=/dev/vda
TUX_WIPE_CONFIRMED=1
TUX_ENCRYPT=$( ((LUKS)) && echo yes || echo no)
TUX_LUKS_PASSWORD=$LUKS_PASS
TUX_HOSTNAME=ci-$DISTRO
TUX_USER=tux
TUX_PASSWORD=tux
TUX_TIMEZONE=UTC
TUX_GEOIP=no
TUX_LOCALE=en_US.UTF-8
TUX_KEYMAP=us
TUX_SESSION=$SESSION
TUX_NVIDIA=no
TUX_THEME=gruvbox
TUX_FONT=jetbrains
TUX_FONT_SIZE=11
TUX_BROWSER=none
TUX_BUNDLES="firewall flatpak"
TUX_EXTRA=""
TUX_EXCLUDE=""
EOF
cat >"$W/post-hook.sh" <<EOF
#!/bin/bash
# CI only: on first boot run vm-check as tux, upload the verdict, power off.
set -e
echo 'tux ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/99-ci; chmod 440 /etc/sudoers.d/99-ci
cat >/usr/local/sbin/tuxcraft-ci <<'EOS'
#!/bin/bash
url=http://10.0.2.2:$PORT
for i in \$(seq 1 60); do curl -fsS -o /tmp/check "\$url/check" && break; sleep 5; done
curl -fsS -T /dev/null "\$url/booted" || true
runuser -u tux -- bash /tmp/check >/tmp/check.out 2>&1; rc=\$?
curl -fsS -T /tmp/check.out "\$url/result-\$rc.txt" || true
poweroff
EOS
chmod 755 /usr/local/sbin/tuxcraft-ci
if [ -d /etc/runit/runsvdir ]; then
  mkdir -p /etc/sv/tuxcraft-ci
  printf '#!/bin/sh\nsleep 20\nexec /usr/local/sbin/tuxcraft-ci\n' >/etc/sv/tuxcraft-ci/run
  chmod 755 /etc/sv/tuxcraft-ci/run
  ln -s /etc/sv/tuxcraft-ci /etc/runit/runsvdir/default/
else
  cat >/etc/systemd/system/tuxcraft-ci.service <<'EOS'
[Unit]
Description=tuxcraft CI check
Wants=network-online.target
After=network-online.target graphical.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/tuxcraft-ci
[Install]
WantedBy=multi-user.target
EOS
  systemctl enable tuxcraft-ci.service
fi
EOF
echo "http://10.0.2.2:$PORT/up" >"$W/report-url"
truncate -s 16M "$CFG"; mkfs.vfat -n TUXCFG "$CFG" >/dev/null
mcopy -i "$CFG" "$W/answers.conf" "$W/post-hook.sh" "$W/report-url" ::/

python3 "$HERE/ci-server.py" "$SERVE" "$PORT" 2>"$W/http.log" &
HTTP_PID=$!
cleanup() { kill "$HTTP_PID" 2>/dev/null || true; [[ -n ${QPID:-} ]] && kill "$QPID" 2>/dev/null || true; }
trap cleanup EXIT

qemu() {  # qemu TIMEOUT extra-args...
  local t=$1; shift
  timeout --foreground "$t" qemu-system-x86_64 "${KVM[@]}" -machine q35 -m "$RAM" -smp "$CPUS" -no-reboot \
    "${FW_ARGS[@]}" -nic user,model=virtio-net-pci -device virtio-vga -display none \
    -serial "file:$W/serial-$PHASE.log" -monitor "unix:$MON,server,nowait" "$@"
}

# ------------------------------------------------------------------ 1: install
PHASE=install
echo ":: phase 1: install from $(basename "$ISO") (timeout ${TIMEOUT_INSTALL}s)"
rc=0
qemu "$TIMEOUT_INSTALL" \
  -drive "file=$DISK,if=virtio,format=qcow2,discard=unmap" \
  -drive "file=$CFG,if=virtio,format=raw" \
  -drive "file=$ISO,media=cdrom,readonly=on" -boot d || rc=$?
log=$(compgen -G "$SERVE/up/install-*.log" | head -n1 || true)
[[ -n $log ]] || { echo "!! no install report (qemu rc $rc: 124 = timeout)"; exit 1; }
irc=${log##*/install-}; irc=${irc%.log}
echo ":: install exit code $irc"
tail -n 40 "$log"
cp "$log" "$W/install.log"
[[ $irc == 0 ]] || exit 1

# ------------------------------------------------------------------ 2: first boot + vm-check
PHASE=boot
echo ":: phase 2: boot the installed system (timeout ${TIMEOUT_BOOT}s)"
qemu "$TIMEOUT_BOOT" -drive "file=$DISK,if=virtio,format=qcow2,discard=unmap" -boot c &
QPID=$!
sendkeys() {  # type a string + Enter through the QEMU monitor
  local s=$1 i c
  for ((i = 0; i < ${#s}; i++)); do c=${s:i:1}; echo "sendkey $c"; sleep 0.05; done
  echo "sendkey ret"
}
start=$SECONDS next=25
while kill -0 "$QPID" 2>/dev/null; do
  compgen -G "$SERVE/up/result-*" >/dev/null && break
  if ((LUKS)) && [[ ! -e $SERVE/up/booted ]] && ((SECONDS - start >= next)); then
    # GRUB's passphrase prompt: typing again later lands harmlessly on the login screen.
    sendkeys "$LUKS_PASS" | python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
for line in sys.stdin: s.sendall(line.encode())
' "$MON" 2>/dev/null || true
    next=$((next + 40))
  fi
  sleep 3
done
wait "$QPID" 2>/dev/null || true
QPID=''
res=$(compgen -G "$SERVE/up/result-*" | head -n1 || true)
[[ -n $res ]] || { echo "!! installed system did not report back"; tail -n 50 "$W/serial-boot.log" 2>/dev/null; exit 1; }
cat "$res"
crc=${res##*/result-}; crc=${crc%.txt}
echo ":: vm-check exit code $crc"
exit "$crc"
