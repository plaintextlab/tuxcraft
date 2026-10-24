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
  fi
  # Root stays locked: administration goes through sudo, which is logged and safer.
  passwd -l root >/dev/null 2>&1 || true
  mkdir -p /etc/sudoers.d
  echo '%wheel ALL=(ALL:ALL) ALL' >/etc/sudoers.d/10-wheel
  chmod 440 /etc/sudoers.d/10-wheel
}

sys_bootloader() {
  step "Installing GRUB ($BOOT_MODE)"
  local cmdline='loglevel=3 quiet'
  [[ ${TUX_NVIDIA:-no} == yes ]] && cmdline+=' nvidia-drm.modeset=1'
  if [[ -f /etc/default/grub ]]; then
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\"|" /etc/default/grub
    sed -i 's|^#\?GRUB_TIMEOUT=.*|GRUB_TIMEOUT=3|' /etc/default/grub
    # Remember the last booted entry so picking linux-lts once sticks until changed.
    grep -q '^GRUB_DEFAULT=saved' /etc/default/grub || sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=saved|' /etc/default/grub
    grep -q '^GRUB_SAVEDEFAULT' /etc/default/grub || echo 'GRUB_SAVEDEFAULT=true' >>/etc/default/grub
    # Arch default ordering would otherwise put linux-lts first.
    grep -q '^GRUB_TOP_LEVEL' /etc/default/grub || [[ $DISTRO != arch ]] || echo 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux"' >>/etc/default/grub
  fi
  if [[ $BOOT_MODE == uefi ]]; then
    run grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=tuxcraft --recheck \
      || die "grub-install failed"
    # Fallback path for firmware that forgets NVRAM entries.
    run grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable || true
  else
    run grub-install --target=i386-pc "$TUX_DISK" || die "grub-install failed"
  fi
  sys_initramfs
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
  # Prefer RAM over compressed swap only when needed; good default for zram.
  echo 'vm.swappiness = 100' >/etc/sysctl.d/99-tuxcraft-zram.conf
}

# Package manager defaults that make updates pleasant and safe.
sys_pkgmanager() {
  step "Tuning $DISTRO package management"
  case $DISTRO in
    arch)
      sed -i -e 's/^#Color/Color/' -e 's/^#VerbosePkgLists/VerbosePkgLists/' \
             -e 's/^#\?ParallelDownloads.*/ParallelDownloads = 8/' /etc/pacman.conf
      grep -q '^ILoveCandy' /etc/pacman.conf || sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
      if has_word "$TUX_BUNDLES" gaming && ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>/etc/pacman.conf
      fi
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
      svc_enable dbus elogind NetworkManager chronyd cronie socklog-unix nanoklogd
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
