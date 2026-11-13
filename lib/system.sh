# shellcheck shell=bash
# Base system configuration. Runs inside the installed system (chroot during a fresh install).

sys_identity() {
  step "Hostname, timezone, locale, keyboard"
  echo "$TUX_HOSTNAME" >/etc/hostname
  cat >/etc/hosts <<EOF
127.0.0.1  localhost
::1        localhost
127.0.1.1  $TUX_HOSTNAME.localdomain $TUX_HOSTNAME
EOF

  if [[ -e /usr/share/zoneinfo/$TUX_TIMEZONE ]]; then
    ln -sf "/usr/share/zoneinfo/$TUX_TIMEZONE" /etc/localtime
    [[ $DISTRO == debian ]] && echo "$TUX_TIMEZONE" >/etc/timezone
  else
    warn "Unknown timezone $TUX_TIMEZONE, leaving UTC"
  fi
  hwclock --systohc 2>/dev/null || true

  local loc=$TUX_LOCALE
  case $DISTRO in
    arch|debian)
      grep -q "^# *$loc UTF-8" /etc/locale.gen && sed -i "s/^# *$loc UTF-8/$loc UTF-8/" /etc/locale.gen
      grep -q "^$loc UTF-8" /etc/locale.gen || echo "$loc UTF-8" >>/etc/locale.gen
      grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen
      run locale-gen
      echo "LANG=$loc" >/etc/locale.conf
      [[ $DISTRO == debian ]] && run update-locale "LANG=$loc"
      ;;
    void)
      if [[ -f /etc/default/libc-locales ]]; then
        sed -i "s/^#\s*$loc UTF-8/$loc UTF-8/" /etc/default/libc-locales
        run xbps-reconfigure -f glibc-locales
      fi
      echo "LANG=$loc" >/etc/locale.conf
      ;;
  esac

  # Console keymap (xkb "gb" is "uk" on the console)
  local kmap=$TUX_KEYMAP
  [[ $kmap == gb ]] && kmap=uk
  case $DISTRO in
    arch) echo "KEYMAP=$kmap" >/etc/vconsole.conf ;;
    void) sed -i "s/^#\?KEYMAP=.*/KEYMAP=$kmap/" /etc/rc.conf ;;
    debian)
      cat >/etc/default/keyboard <<EOF
XKBMODEL="pc105"
XKBLAYOUT="$TUX_KEYMAP"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF
      # debootstrap leaves CHARMAP="ISO-8859-15": the console is then not in UTF-8 mode and
      # tuigreet's box-drawing borders come out as "âöÇâöÇ". The font is set by tux-console.
      cat >/etc/default/console-setup <<EOF
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="guess"
FONTFACE="Fixed"
FONTSIZE="8x16"
VIDEOMODE=
EOF
      # Rebuild the cached boot scripts; the old ones (udev runs them on every new VT) still
      # switch each console to ISO-8859-15.
      setupcon --save-only 2>/dev/null || warn "Could not rebuild the console-setup cache"
      ;;
  esac
  # X11 layout; sway reads its own input config (written by the desktop stage)
  mkdir -p /etc/X11/xorg.conf.d
  cat >/etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$TUX_KEYMAP"
EndSection
EOF
}

sys_user() {
  step "Creating user $TUX_USER"
  local groups='wheel' g
  getent group wheel >/dev/null || groupadd -r wheel
  for g in audio video input storage lp lpadmin network sudo docker; do
    getent group "$g" >/dev/null && groups+=",$g"
  done
  if id "$TUX_USER" &>/dev/null; then
    usermod -aG "$groups" "$TUX_USER"
  else
    useradd -m -s /bin/bash -G "$groups" "$TUX_USER"
  fi
  if [[ -n ${TUX_PASSWORD:-} ]]; then
    echo "$TUX_USER:$TUX_PASSWORD" | chpasswd
    # Void's PAM-enabled chpasswd exits 0 without writing anything; check and fall back to a hash.
    if [[ $(getent shadow "$TUX_USER" | cut -d: -f2) != \$* ]]; then
      command -v openssl >/dev/null || pkg_install openssl
      echo "$TUX_USER:$(openssl passwd -6 -stdin <<<"$TUX_PASSWORD")" | chpasswd -e
    fi
    [[ $(getent shadow "$TUX_USER" | cut -d: -f2) == \$* ]] || die "Could not set the password for $TUX_USER"
  fi
  # Root stays locked: administration goes through sudo, which is logged and safer.
  passwd -l root >/dev/null 2>&1 || true
  mkdir -p /etc/sudoers.d
  echo '%wheel ALL=(ALL:ALL) ALL' >/etc/sudoers.d/10-wheel
  chmod 440 /etc/sudoers.d/10-wheel
}

# Disk facts from the live stage (lib/disk.sh write_disk_conf).
load_disk_conf() {
  TUX_LUKS_UUID='' TUX_DUALBOOT=0 TUX_ROOT_PART=''
  # shellcheck source=/dev/null
  [[ -r $TUX_ETC/disk.conf ]] && . "$TUX_ETC/disk.conf"
  return 0
}

# set_grub KEY VALUE : set (or add) one /etc/default/grub variable.
set_grub() {
  local f=/etc/default/grub
  [[ -f $f ]] || return 0
  if grep -qE "^#?\s*$1=" "$f"; then sed -i -E "s|^#?\s*$1=.*|$1=$2|" "$f"; else echo "$1=$2" >>"$f"; fi
}

# Encrypted root: the initramfs opens it with the key file (GRUB already asked for the passphrase).
sys_crypt() {
  [[ -n $TUX_LUKS_UUID ]] || return 0
  step "Disk encryption: initramfs unlock with the key file"
  local kf=/etc/cryptsetup-keys.d/cryptroot.key
  [[ -r $kf ]] || die "Key file $kf missing"
  chmod 700 /etc/cryptsetup-keys.d; chmod 600 "$kf"
  case $DISTRO in
    arch)
      command -v cryptsetup >/dev/null || pkg_install cryptsetup
      local conf=/etc/mkinitcpio.conf
      if grep -qE '^HOOKS=.*\bsystemd\b' "$conf"; then
        # systemd-based initramfs (Arch's default): sd-encrypt reads crypttab.initramfs.
        grep -qE '^HOOKS=.*\bsd-encrypt\b' "$conf" || sed -i -E 's/^(HOOKS=.*)\bfilesystems\b/\1sd-encrypt filesystems/' "$conf"
        echo "cryptroot UUID=$TUX_LUKS_UUID $kf luks,discard" >/etc/crypttab.initramfs
      else
        grep -qE '^HOOKS=.*\bencrypt\b' "$conf" || sed -i -E 's/^(HOOKS=.*)\bfilesystems\b/\1encrypt filesystems/' "$conf"
        GRUB_CRYPT_CMDLINE="cryptdevice=UUID=$TUX_LUKS_UUID:cryptroot:allow-discards cryptkey=rootfs:$kf"
      fi
      grep -qE '^HOOKS=.*\bkeyboard\b' "$conf" || warn "mkinitcpio HOOKS has no keyboard hook; a passphrase fallback prompt would get no input"
      if grep -q '^FILES=' "$conf"; then
        grep -qF "$kf" "$conf" || sed -i -E "s|^FILES=\((.*)\)|FILES=(\1 $kf)|" "$conf"
      else
        echo "FILES=($kf)" >>"$conf"
      fi
      ;;
    debian)
      command -v cryptsetup >/dev/null || pkg_install cryptsetup cryptsetup-initramfs
      echo "cryptroot UUID=$TUX_LUKS_UUID $kf luks,discard,key-slot=1" >/etc/crypttab
      mkdir -p /etc/cryptsetup-initramfs
      grep -qs '^KEYFILE_PATTERN=' /etc/cryptsetup-initramfs/conf-hook ||
        echo 'KEYFILE_PATTERN="/etc/cryptsetup-keys.d/*.key"' >>/etc/cryptsetup-initramfs/conf-hook
      # The key file is inside the initramfs: nobody but root may read the image.
      grep -qs '^UMASK=0077' /etc/initramfs-tools/initramfs.conf || echo 'UMASK=0077' >>/etc/initramfs-tools/initramfs.conf
      ;;
    void)
      command -v cryptsetup >/dev/null || pkg_install cryptsetup
      echo "cryptroot UUID=$TUX_LUKS_UUID $kf luks,discard" >/etc/crypttab
      mkdir -p /etc/dracut.conf.d
      cat >/etc/dracut.conf.d/10-tuxcraft-crypt.conf <<EOF
# tuxcraft: unlock the encrypted root with the key file (GRUB already asked for the passphrase)
add_dracutmodules+=" crypt btrfs "
install_items+=" $kf /etc/crypttab "
EOF
      GRUB_CRYPT_CMDLINE="rd.luks.uuid=$TUX_LUKS_UUID rd.luks.allow-discards"
      ;;
  esac
  set_grub GRUB_ENABLE_CRYPTODISK y
}

sys_bootloader() {
  step "Installing GRUB ($BOOT_MODE)"
  local cmdline='loglevel=3 quiet'
  [[ ${TUX_NVIDIA:-no} == yes ]] && cmdline+=' nvidia-drm.modeset=1'
  GRUB_CRYPT_CMDLINE=''
  load_disk_conf
  sys_crypt
  if [[ -f /etc/default/grub ]]; then
    # Crypt parameters go in GRUB_CMDLINE_LINUX so the recovery entries have them too.
    [[ -n $GRUB_CRYPT_CMDLINE ]] && set_grub GRUB_CMDLINE_LINUX "\"$GRUB_CRYPT_CMDLINE\""
    if ((TUX_DUALBOOT)); then
      command -v os-prober >/dev/null || pkg_install os-prober || warn "os-prober not installed: add other systems to GRUB by hand"
      set_grub GRUB_DISABLE_OS_PROBER false
      sed -i 's|^#\?GRUB_TIMEOUT_STYLE=.*|GRUB_TIMEOUT_STYLE=menu|' /etc/default/grub
    fi
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\"|" /etc/default/grub
    sed -i 's|^#\?GRUB_TIMEOUT=.*|GRUB_TIMEOUT=3|' /etc/default/grub
    # Always boot the first entry. No GRUB_SAVEDEFAULT: /boot sits on btrfs, where GRUB cannot
    # write grubenv, and every boot would stop at "error: sparse file not allowed".
    sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=0|; /^GRUB_SAVEDEFAULT=/d' /etc/default/grub
    # Arch default ordering would otherwise put linux-lts first.
    grep -q '^GRUB_TOP_LEVEL' /etc/default/grub || [[ $DISTRO != arch ]] || echo 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux"' >>/etc/default/grub
  fi
  if [[ $BOOT_MODE == uefi ]]; then
    run grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=tuxcraft --recheck \
      || die "grub-install failed"
    # Fallback path for firmware that forgets NVRAM entries. Not on a shared EFI partition:
    # EFI/BOOT/BOOTX64.EFI there belongs to the other system (usually Windows).
    ((TUX_DUALBOOT)) || run grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable || true
  else
    run grub-install --target=i386-pc "$TUX_DISK" || die "grub-install failed"
  fi
  sys_initramfs
  # The initramfs of an encrypted system holds the key file.
  if [[ -n $TUX_LUKS_UUID ]]; then chmod 600 /boot/initr* 2>/dev/null || true; fi
  run grub-mkconfig -o /boot/grub/grub.cfg || die "grub-mkconfig failed"
}

sys_initramfs() {
  case $DISTRO in
    arch)
      if [[ ${TUX_NVIDIA:-no} == yes ]]; then
        # kms hook would pull nouveau into the initramfs before nvidia can claim the GPU
        sed -i -E 's/^(HOOKS=.*) kms(.*)$/\1\2/' /etc/mkinitcpio.conf
      fi
      run mkinitcpio -P ;;
    debian) run update-initramfs -u -k all ;;
    void)   run xbps-reconfigure -fa ;;
  esac
}

sys_zram() {
  case $DISTRO in
    arch|debian)
      pkg_install "$( [[ $DISTRO == arch ]] && echo zram-generator || echo systemd-zram-generator )"
      cat >/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
EOF
      ;;
    void) pkg_install zramen; svc_enable zramen ;;
  esac
}

# Settings that keep the desktop responsive. Runs on install and on every update, so existing
# systems get them too; takes effect at the next boot (or at once on an update, for sysctl).
sys_tuning() {
  mkdir -p /etc/sysctl.d   # absent on a fresh Void base system
  # zram: swap is cheap compressed RAM, so use it freely; read it back one page at a time (no
  # disk seeks to amortise), and don't evict extra cache after a brief memory shortage.
  cat >/etc/sysctl.d/99-tuxcraft-zram.conf <<'EOF'
# tuxcraft: tuned for zram swap (Fedora / Pop!_OS values)
vm.swappiness = 100
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
EOF
  # By default up to 20% of RAM (6 GB with 32 GB) can wait in memory unwritten; flushing that
  # much at once stalls every program that touches the disk. Write it out early and in small parts.
  cat >/etc/sysctl.d/99-tuxcraft-writeback.conf <<'EOF'
# tuxcraft: start writing at 64 MiB of unwritten data, make writers wait at 256 MiB
vm.dirty_background_bytes = 67108864
vm.dirty_bytes = 268435456
EOF
  if [[ ${TUX_MODE:-} != install ]]; then
    sysctl -q -p /etc/sysctl.d/99-tuxcraft-zram.conf /etc/sysctl.d/99-tuxcraft-writeback.conf 2>/dev/null || true
  fi

  # Void's zramen defaults to lz4 at 25% of RAM; match the other distros (zstd, half, max 8 GiB).
  # Only while its conf is untouched (all comments) or ours, so your own edits are kept.
  local zc=/etc/sv/zramen/conf
  if [[ -f $zc ]] && { grep -q '^# tuxcraft' "$zc" || ! grep -qvE '^[[:space:]]*(#|$)' "$zc"; }; then
    cat >"$zc" <<'EOF'
# tuxcraft: same zram as on Arch/Debian (applies at the next boot)
export ZRAM_COMP_ALGORITHM=zstd
export ZRAM_SIZE=50
export ZRAM_MAX_SIZE=8192
EOF
  fi

  # earlyoom: when RAM and swap are nearly gone, end the biggest process at once instead of
  # letting the whole desktop freeze for minutes before the kernel's own OOM killer acts.
  pkg_install earlyoom
  if [[ $INIT == systemd ]] || [[ -d /etc/sv/earlyoom ]]; then svc_enable earlyoom; fi
}

# Linux caches writes in RAM (up to ~20% of it) and lets the copy "finish" before the data is on
# the disk, so a copy to a USB stick races to 100% and then hangs in sync/unmount. Cap the write
# cache of USB disks and SD cards only (kernel 6.2+ strict per-device limit): file managers then
# show the real progress. (Internal disks get the system-wide 256 MiB limit from sys_tuning.)
sys_writeback() {
  mkdir -p /etc/udev/rules.d
  cat >/etc/udev/rules.d/60-tuxcraft-usb-writeback.rules <<'EOF'
# tuxcraft: at most 16 MiB of unwritten data per USB disk / SD card, so copy progress is real
ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_BUS}=="usb", ATTR{bdi/strict_limit}="1", ATTR{bdi/max_bytes}="16777216"
ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", KERNEL=="mmcblk[0-9]*", ATTRS{type}=="SD", ATTR{bdi/strict_limit}="1", ATTR{bdi/max_bytes}="16777216"
EOF
  # Apply now to disks already plugged in (no-op in the installer chroot, where udevd is not running).
  if udevadm control --reload 2>/dev/null; then
    udevadm trigger --subsystem-match=block --action=change 2>/dev/null || true
  fi
}

# Package manager defaults that make updates pleasant and safe.
sys_pkgmanager() {
  step "Tuning $DISTRO package management"
  case $DISTRO in
    arch)
      sed -i -e 's/^#Color/Color/' -e 's/^#VerbosePkgLists/VerbosePkgLists/' \
             -e 's/^#\?ParallelDownloads.*/ParallelDownloads = 8/' /etc/pacman.conf
      grep -q '^ILoveCandy' /etc/pacman.conf || sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
      # multilib (32-bit libraries) always: Steam, Wine and many games need it later even when the
      # gaming extras were not picked. Uncomment Arch's own section, or add one if it is missing.
      sed -i '/^#\[multilib\]$/,/^#Include/ s/^#//' /etc/pacman.conf
      grep -q '^\[multilib\]' /etc/pacman.conf || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>/etc/pacman.conf
      pkg_refresh
      pkg_install_groups hygiene
      # Keep 2 package versions in cache (enough to downgrade), purge the rest weekly.
      mkdir -p /etc/systemd/system/paccache.service.d
      printf '[Service]\nExecStart=\nExecStart=/usr/bin/paccache -rk2\n' >/etc/systemd/system/paccache.service.d/keep2.conf
      svc_enable paccache.timer
      if [[ -f /etc/xdg/reflector/reflector.conf ]]; then
        cat >/etc/xdg/reflector/reflector.conf <<'EOF'
--save /etc/pacman.d/mirrorlist
--protocol https
--latest 15
--sort rate
--age 12
EOF
        svc_enable reflector.timer
      fi
      ;;
    debian)
      if has_word "$TUX_BUNDLES" gaming; then dpkg --add-architecture i386; fi
      pkg_refresh
      pkg_install_groups hygiene
      # Security updates install themselves; everything else waits for `sysup`.
      cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
      ;;
    void)
      pkg_refresh
      if has_word "$TUX_BUNDLES" gaming; then
        pkg_install void-repo-multilib void-repo-multilib-nonfree; pkg_refresh
      fi
      pkg_install_groups hygiene
      ;;
  esac
}

sys_services() {
  step "Enabling system services"
  case $DISTRO in
    arch|debian)
      svc_enable NetworkManager systemd-timesyncd fstrim.timer
      ;;
    void)
      pkg_install_groups core   # dbus/elogind/chrony/cronie are in core for void
      svc_disable dhcpcd wpa_supplicant
      # elogind is left to D-Bus activation: greetd's PAM session activates it before the runit
      # service gets going, and the service then restarts every second ("already running").
      svc_enable dbus NetworkManager chronyd cronie socklog-unix nanoklogd
      ;;
  esac
}

# Fresh-install only: everything that a distro installer would normally do.
system_stage() {
  sys_identity
  sys_pkgmanager
  sys_user
  sys_zram
  sys_services
}
