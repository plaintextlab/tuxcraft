# shellcheck shell=bash
# Graphics drivers. Open drivers (mesa) always; NVIDIA proprietary only when asked.

gpu_stage() {
  step "Graphics drivers (${GPU_VENDORS:-unknown})"
  local -a p=()
  case $DISTRO in
    arch)   p+=(mesa vulkan-icd-loader libva-utils) ;;
    debian) p+=(mesa-vulkan-drivers libgl1-mesa-dri va-driver-all vainfo) ;;
    void)   p+=(mesa-dri vulkan-loader libva-utils) ;;
  esac
  if has_word "$GPU_VENDORS" intel; then
    case $DISTRO in
      arch)   p+=(vulkan-intel intel-media-driver) ;;
      debian) p+=(intel-media-va-driver-non-free) ;;
      void)   p+=(mesa-vulkan-intel intel-video-accel) ;;
    esac
  fi
  if has_word "$GPU_VENDORS" amd; then
    case $DISTRO in
      arch)   p+=(vulkan-radeon) ;;
      debian) p+=(firmware-amd-graphics) ;;
      void)   p+=(mesa-vulkan-radeon mesa-vaapi) ;;
    esac
  fi
  # Steam and 32-bit games (Proton) need the 32-bit drivers too; without them pacman asks which
  # lib32 Vulkan driver to pick, and the iGPU has no 32-bit GL at all.
  if [[ $DISTRO == arch ]] && has_word "$TUX_BUNDLES" gaming; then
    p+=(lib32-mesa lib32-vulkan-icd-loader)
    has_word "$GPU_VENDORS" amd && p+=(lib32-vulkan-radeon)
    has_word "$GPU_VENDORS" intel && p+=(lib32-vulkan-intel)
  fi
  if has_word "$GPU_VENDORS" vm; then
    case $DISTRO in
      arch|debian) p+=(spice-vdagent qemu-guest-agent) ;;
      void)        p+=(spice-vdagent qemu-ga) ;;
    esac
  fi
  pkg_install "${p[@]}"

  [[ ${TUX_NVIDIA:-no} == yes ]] || return 0
  info "Installing NVIDIA proprietary driver ($NVIDIA_GEN GPU)"
  p=()
  case $DISTRO in
    arch)
      if [[ $NVIDIA_GEN == legacy ]]; then
        warn "Pascal/Maxwell and older need nvidia-580xx-dkms from the AUR. Keeping nouveau for now;"
        warn "after first boot run:  paru -S nvidia-580xx-dkms nvidia-580xx-utils"
        TUX_NVIDIA=no; return 0
      fi
      p+=(nvidia-open-dkms nvidia-utils nvidia-settings nvidia-prime libva-nvidia-driver)
      has_word "$TUX_BUNDLES" gaming && p+=(lib32-nvidia-utils)
      ;;
    debian)
      # Headers first, in their own step: DKMS builds the module while the driver installs.
      # linux-headers-amd64, not linux-headers-$(uname -r): in the chroot uname is the live ISO's.
      pkg_install linux-headers-amd64
      if [[ $NVIDIA_GEN == legacy ]]; then
        p+=(nvidia-kernel-dkms nvidia-driver nvidia-modprobe)
      elif nvidia_debian_repo; then
        p+=(nvidia-open nvidia-modprobe)
      else
        warn "Could not add NVIDIA's repository; trying Debian's own driver"
        p+=(nvidia-open-kernel-dkms nvidia-driver nvidia-modprobe)
      fi
      p+=(firmware-misc-nonfree nvidia-settings)
      ;;
    void)
      pkg_install void-repo-nonfree; pkg_refresh
      p+=(nvidia)
      has_word "$TUX_BUNDLES" gaming && p+=(nvidia-libs-32bit)
      ;;
  esac
  pkg_install "${p[@]}"
  mkdir -p /etc/modprobe.d
  cat >/etc/modprobe.d/nvidia-tuxcraft.conf <<'EOF'
# Kernel modesetting is required for Wayland and for a tear-free X11 PRIME setup.
options nvidia_drm modeset=1 fbdev=1
# Keep VRAM contents across suspend so the session survives sleep.
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
  nvidia_uvm_setup
  if [[ $INIT == systemd ]]; then
    # Debian's and Arch's drivers ship these; NVIDIA's own (Debian, nvidia-open) suspends through
    # systemd drop-ins instead and has none of them.
    local u
    for u in nvidia-suspend nvidia-resume nvidia-hibernate; do
      [[ -e /usr/lib/systemd/system/$u.service || -e /lib/systemd/system/$u.service ]] && svc_enable "$u.service"
    done
    # Dynamic Boost: shifts power between CPU and GPU on Ampere+ laptops (no-op elsewhere).
    if ((IS_LAPTOP)) && [[ -e /usr/lib/systemd/system/nvidia-powerd.service || -e /lib/systemd/system/nvidia-powerd.service ]]; then svc_enable nvidia-powerd.service; fi
  fi
}

# Debian's own NVIDIA driver trails its kernel: 550.163.01 no longer builds on 6.12.115
# (pci_resize_resource changed), so modern GPUs get NVIDIA's repository for Debian and its
# nvidia-open driver, as NVIDIA documents. Its versions are newer, so apt prefers them.
nvidia_debian_repo() {
  local v deb=/tmp/cuda-keyring.deb
  v=$(. /etc/os-release && echo "${VERSION_ID%%.*}")
  [[ -n $v ]] || return 1
  info "Adding NVIDIA's repository for Debian $v"
  fetch "https://developer.download.nvidia.com/compute/cuda/repos/debian$v/x86_64/cuda-keyring_1.1-1_all.deb" "$deb" || return 1
  run dpkg -i "$deb" || return 1
  rm -f "$deb"
  pkg_refresh
  pkg_available nvidia-open
}

# CUDA and NVENC (OBS, Blender, DaVinci Resolve, Flatpak apps) need /dev/nvidia-uvm. Loading the
# nvidia_uvm module does not create it: a CUDA program normally does, through the setuid helper
# nvidia-modprobe, but Flatpak sandboxes cannot run it, so Flatpak OBS reports "cuda_init_999"
# and falls back to x264. Arch's driver ships a udev rule for this; Void's and Debian's do not.
nvidia_uvm_setup() {
  mkdir -p /etc/modules-load.d /etc/udev/rules.d
  [[ -f /etc/modules-load.d/nvidia-uvm.conf ]] || echo nvidia-uvm >/etc/modules-load.d/nvidia-uvm.conf
  local mp rules=/etc/udev/rules.d/70-tuxcraft-nvidia-uvm.rules
  mp=$(command -v nvidia-modprobe || true)
  {
    echo '# tuxcraft: create /dev/nvidia-uvm(-tools) when the module loads (CUDA/NVENC, Flatpak OBS).'
    if [[ -n $mp ]]; then
      echo "ACTION==\"add\", SUBSYSTEM==\"module\", KERNEL==\"nvidia_uvm\", RUN+=\"$mp -c0 -u\""
    else
      # No nvidia-modprobe: make the nodes from the major number in /proc/devices.
      echo 'ACTION=="add", SUBSYSTEM=="module", KERNEL=="nvidia_uvm", RUN+="/bin/sh -c '"'"'m=$$(grep nvidia-uvm /proc/devices | cut -d\  -f1); mknod -m 666 /dev/nvidia-uvm c $$m 0; mknod -m 666 /dev/nvidia-uvm-tools c $$m 1'"'"'"'
    fi
  } >"$rules"
  # runit (Void): modules can load before udevd runs; make sure at the end of boot as well.
  if [[ $INIT != systemd && -n $mp ]] && ! grep -qs 'nvidia-modprobe' /etc/rc.local; then
    printf '\n# tuxcraft: /dev/nvidia-uvm for CUDA/NVENC (see %s)\n%s -c0 -u 2>/dev/null || true\n' "$rules" "$mp" >>/etc/rc.local
  fi
  # Right away too, so the running desktop gets it without a reboot.
  if [[ -n $mp ]] && grep -q '^nvidia_uvm ' /proc/modules 2>/dev/null; then "$mp" -c0 -u 2>/dev/null || true; fi
  return 0
}
