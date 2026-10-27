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
      if [[ $NVIDIA_GEN == legacy ]]; then p+=(nvidia-kernel-dkms); else p+=(nvidia-open-kernel-dkms); fi
      p+=(nvidia-driver firmware-misc-nonfree nvidia-settings linux-headers-amd64)
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
  if [[ $INIT == systemd ]]; then
    svc_enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service
    # Dynamic Boost: shifts power between CPU and GPU on Ampere+ laptops (no-op elsewhere).
    ((IS_LAPTOP)) && [[ $DISTRO == arch ]] && svc_enable nvidia-powerd.service
  fi
}
