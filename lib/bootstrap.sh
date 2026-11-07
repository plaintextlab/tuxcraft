# shellcheck shell=bash
# Install a minimal base system into $TARGET from the distro's own live ISO.
# Everything after this runs inside the new system (chroot), see lib/system.sh.

chroot_setup() {
  mountpoint -q "$TARGET/proc" || mount -t proc proc "$TARGET/proc"
  mountpoint -q "$TARGET/sys"  || { mount --rbind /sys "$TARGET/sys"; mount --make-rslave "$TARGET/sys"; }
  mountpoint -q "$TARGET/dev"  || { mount --rbind /dev "$TARGET/dev"; mount --make-rslave "$TARGET/dev"; }
  mountpoint -q "$TARGET/run"  || mount -t tmpfs tmpfs "$TARGET/run"
  mkdir -p "$TARGET/etc"
  rm -f "$TARGET/etc/resolv.conf"
  cp -L /etc/resolv.conf "$TARGET/etc/resolv.conf" 2>/dev/null || true
}

ucode_pkg() {
  case "$DISTRO:$CPU_VENDOR" in
    arch:intel) echo intel-ucode ;;  arch:amd) echo amd-ucode ;;
    debian:intel) echo intel-microcode ;; debian:amd) echo amd64-microcode ;;
    void:intel) echo intel-ucode ;;  void:amd) echo linux-firmware-amd ;;
  esac
}

grub_pkgs() {
  case "$DISTRO:$BOOT_MODE" in
    arch:uefi)   echo grub efibootmgr ;;
    arch:bios)   echo grub ;;
    debian:uefi) echo grub-efi-amd64 efibootmgr ;;
    debian:bios) echo grub-pc ;;
    void:uefi)   echo grub-x86_64-efi efibootmgr ;;
    void:bios)   echo grub ;;
  esac
}

bootstrap_arch() {
  step "Installing Arch Linux base (pacstrap)"
  sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 8/' /etc/pacman.conf
  run pacman -Sy --noconfirm archlinux-keyring || warn "Could not refresh keyring, continuing"
  # Two kernels: if an update to 'linux' ever breaks boot, pick 'linux-lts' in GRUB.
  # shellcheck disable=SC2046
  run pacstrap -K "$TARGET" base linux linux-lts linux-headers linux-lts-headers linux-firmware \
      $(ucode_pkg) $(grub_pkgs) btrfs-progs dosfstools sudo networkmanager pciutils curl git \
      zram-generator vim man-db bash-completion || die "pacstrap failed (see $TUX_LOG)"
}

DEBIAN_KEYRING=/usr/share/keyrings/debian-archive-keyring.gpg

# debootstrap verifies every package against Debian's archive key. A Debian host has it; on
# other hosts it comes from the distro (Arch packages it) or from the pinned keyring .deb.
debian_keyring() {
  [[ -s $DEBIAN_KEYRING ]] && { echo "$DEBIAN_KEYRING"; return; }
  local t=/tmp/tuxcraft-debkeyring
  if [[ ! -s $t/keyring.gpg ]]; then
    rm -rf "$t"; mkdir -p "$t"
    run pin_get debian-keyring "$t/k.deb" || die "Could not download the Debian archive keyring"
    (cd "$t" && bsdtar -xf k.deb && bsdtar -xf data.tar.* ./usr/share/keyrings/debian-archive-keyring.gpg) ||
      die "Could not unpack the Debian archive keyring (bsdtar missing?)"
    mv "$t/usr/share/keyrings/debian-archive-keyring.gpg" "$t/keyring.gpg"
  fi
  echo "$t/keyring.gpg"
}

bootstrap_debian() {
  local suite mirror=http://deb.debian.org/debian keyring
  suite=${TUX_DEBIAN_SUITE:-}
  if [[ -z $suite && $HOST_DISTRO == debian ]]; then
    # shellcheck disable=SC1091
    suite=$(. /etc/os-release; echo "${VERSION_CODENAME:-}")
    [[ $suite =~ ^(sid|unstable)$ ]] && warn "Live system is $suite; installing that suite."
  fi
  suite=${suite:-trixie}
  step "Installing Debian $suite base (debootstrap)"
  keyring=$(debian_keyring)
  run debootstrap --arch=amd64 --keyring="$keyring" --components=main,contrib,non-free,non-free-firmware \
      --include=locales,ca-certificates,curl,git,sudo,dbus,console-setup,keyboard-configuration \
      "$suite" "$TARGET" "$mirror" || die "debootstrap failed (see $TUX_LOG)"
  rm -f "$TARGET/etc/apt/sources.list"
  cat >"$TARGET/etc/apt/sources.list.d/debian.sources" <<EOF
Types: deb
URIs: $mirror
Suites: $suite $suite-updates $suite-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: $suite-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
  chroot_setup
  local crypt=''
  [[ ${TUX_ENCRYPT:-no} == yes ]] && crypt='cryptsetup cryptsetup-initramfs'
  # shellcheck disable=SC2046
  DEBIAN_FRONTEND=noninteractive run chroot "$TARGET" sh -c "apt-get update && apt-get install -y \
      linux-image-amd64 linux-headers-amd64 firmware-linux firmware-linux-nonfree firmware-misc-nonfree \
      $(ucode_pkg) $(grub_pkgs) btrfs-progs dosfstools initramfs-tools network-manager pciutils \
      systemd-timesyncd systemd-zram-generator bash-completion man-db $crypt" || die "Debian base packages failed (see $TUX_LOG)"
}

# On a Void host the system xbps; anywhere else the static build from Void (pinned + verified),
# which also brings Void's repository signing keys: packages stay signature-checked.
XBPS=xbps-install XBPS_KEYS=/var/db/xbps/keys
void_xbps() {
  [[ $HOST_DISTRO == void ]] && return 0
  local t=/tmp/tuxcraft-xbps
  if [[ ! -x $t/usr/bin/xbps-install.static ]]; then
    rm -rf "$t"; mkdir -p "$t"
    run pin_get xbps-static "$t/x.txz" || die "Could not download the static xbps"
    tar -xJf "$t/x.txz" -C "$t" || die "Could not unpack the static xbps"
  fi
  XBPS=$t/usr/bin/xbps-install.static XBPS_KEYS=$t/var/db/xbps/keys
  compgen -G "$XBPS_KEYS/*.plist" >/dev/null || die "The static xbps came without Void's signing keys"
  # Hosts without xbps have no xbps config: tell it where its own files are.
  mkdir -p "$t/etc/xbps.d"
}

bootstrap_void() {
  local mirror repo arch
  arch=x86_64
  void_xbps
  step "Picking the fastest Void mirror"
  mirror=$(bash "$TUX_SRC/bin/tux-mirror" --best) || warn "No mirror answered the speed test; using the default"
  mirror=${mirror:-https://repo-default.voidlinux.org}
  info "Mirror: $mirror"
  repo=$mirror/current
  # Only a musl Void host installs musl Void; everything else installs glibc.
  # (grep >/dev/null, not -q: under pipefail an early-quitting grep can turn a match into failure)
  if [[ $HOST_DISTRO == void ]] && ldd --version 2>&1 | grep -i musl >/dev/null; then repo+=/musl; arch+=-musl; fi
  step "Installing Void Linux base (xbps, $arch)"
  [[ $HOST_DISTRO == void ]] && { run xbps-install -Syu -R "$repo" xbps || true; }
  mkdir -p "$TARGET/var/db/xbps/keys"
  cp -a "$XBPS_KEYS"/. "$TARGET/var/db/xbps/keys/"
  # shellcheck disable=SC2046
  XBPS_ARCH=$arch run "$XBPS" -Sy -r "$TARGET" -R "$repo" base-system void-repo-nonfree \
      $(grub_pkgs) btrfs-progs dosfstools sudo NetworkManager pciutils curl git bash-completion \
      zramen dbus elogind cryptsetup || die "xbps base install failed (see $TUX_LOG)"
  # Microcode for Intel lives in the nonfree repo, which only exists after void-repo-nonfree.
  local uc; uc=$(ucode_pkg)
  if [[ -n $uc ]]; then XBPS_ARCH=$arch run "$XBPS" -Sy -r "$TARGET" -R "$repo" -R "$repo/nonfree" "$uc" || true; fi
  # Every repository file (main, nonfree, later multilib) on the same mirror; remembered for later.
  run bash "$TUX_SRC/bin/tux-mirror" -r "$TARGET" "$mirror" ||
    { mkdir -p "$TARGET/etc/xbps.d"; echo "repository=$repo" >"$TARGET/etc/xbps.d/00-repository-main.conf"; }
}

live_prereqs() {
  step "Preparing live environment"
  ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 || curl -fsI https://github.com >/dev/null 2>&1 || die "No internet. Connect first (Wi-Fi: see 'Connecting to the internet' in the README) and re-run."
  # Host tools: partitioning, btrfs, LUKS, and the bootstrap tool of the distro being installed.
  # The tuxcraft ISO ships all of them; the distros' own live ISOs get what they lack.
  local -a need=(btrfs-progs dosfstools cryptsetup)
  [[ $DISTRO == debian && $HOST_DISTRO != debian ]] && need+=(debootstrap)
  case $HOST_DISTRO in
    arch)
      [[ $DISTRO == debian ]] && need+=(debootstrap debian-archive-keyring)
      ((IS_TUXISO)) || run pacman -Sy --needed --noconfirm "${need[@]}" ;;
    debian)
      run apt-get update
      run apt-get install -y debootstrap "${need[@]}" parted ;;
    void)
      run xbps-install -Sy xbps || true
      [[ $DISTRO == debian ]] && need+=(bsdtar)
      run xbps-install -y "${need[@]}" parted || true ;;
  esac
  for t in sfdisk mkfs.btrfs mkfs.fat wipefs blkid findmnt cryptsetup; do
    command -v "$t" >/dev/null || [[ $t == mkfs.fat && $BOOT_MODE == bios ]] || die "Missing tool on live system: $t"
  done
  [[ $DISTRO == debian ]] && { command -v debootstrap >/dev/null || die "Missing tool on live system: debootstrap"; }
  return 0
}

# Unmount the new system and lock the encrypted disk again.
target_release() {
  sync
  umount -R "$TARGET" 2>/dev/null || warn "Could not unmount $TARGET cleanly"
  if [[ -e /dev/mapper/$CRYPT_NAME ]]; then cryptsetup close "$CRYPT_NAME" 2>/dev/null || warn "Could not close $CRYPT_NAME"; fi
  return 0
}

# A NetworkManager Wi-Fi profile: write_nm_wifi FILE SSID PSK
write_nm_wifi() {
  cat >"$1" <<EOF
[connection]
id=$2
uuid=$(cat /proc/sys/kernel/random/uuid)
type=wifi

[wifi]
mode=infrastructure
ssid=$2

[wifi-security]
key-mgmt=wpa-psk
psk=$3

[ipv4]
method=auto

[ipv6]
method=auto
EOF
}

# Wi-Fi joined on the live ISO (iwd on Arch, wpa_supplicant on Debian/Void, or NetworkManager)
# works on first boot too.
carry_over_wifi() {
  local dst=$TARGET/etc/NetworkManager/system-connections f ssid psk n=0
  mkdir -p "$dst"
  if compgen -G '/etc/NetworkManager/system-connections/*.nmconnection' >/dev/null; then
    cp -a /etc/NetworkManager/system-connections/*.nmconnection "$dst"/ && n=1
  fi
  for f in /var/lib/iwd/*.psk; do
    [[ -f $f ]] || continue
    ssid=$(basename "$f" .psk)
    [[ $ssid == =* ]] && continue   # hex-encoded SSID, too unusual to translate safely
    psk=$(sed -n 's/^Passphrase=//p' "$f")
    [[ -n $psk ]] || continue
    write_nm_wifi "$dst/$ssid.nmconnection" "$ssid" "$psk"
    n=1
  done
  # Debian / Void live: networks added with wpa_passphrase (see the README). One "ssid<TAB>psk"
  # line per network block; psk is the passphrase, or the 64-hex key NetworkManager also accepts.
  local wpa=/etc/wpa_supplicant/wpa_supplicant.conf
  if [[ -f $wpa ]]; then
    while IFS=$'\t' read -r ssid psk; do
      [[ -n $ssid && -n $psk && $ssid != */* ]] || continue
      [[ -f $dst/$ssid.nmconnection ]] && continue
      write_nm_wifi "$dst/$ssid.nmconnection" "$ssid" "$psk"
      n=1
    done < <(awk '
      /^[ \t]*network=\{/ { ssid = ""; pass = ""; hex = ""; open = 1; next }
      open && /^[ \t]*ssid="/   { sub(/^[ \t]*ssid="/, ""); sub(/"[ \t]*$/, ""); ssid = $0 }
      open && /^[ \t]*#psk="/   { sub(/^[ \t]*#psk="/, ""); sub(/"[ \t]*$/, ""); pass = $0 }
      open && /^[ \t]*psk=/     { sub(/^[ \t]*psk=/, ""); gsub(/[ \t"]/, ""); hex = $0 }
      open && /^[ \t]*\}/       { if (ssid != "") print ssid "\t" (pass != "" ? pass : hex); open = 0 }
    ' "$wpa")
  fi
  chmod 600 "$dst"/*.nmconnection 2>/dev/null || true
  ((n)) && info "Wi-Fi from the live system copied to the new one"
  return 0
}

bootstrap_base() {  # after live_prereqs and disk_prepare
  "bootstrap_$DISTRO"
  write_fstab
  carry_over_wifi
  chroot_setup
}
