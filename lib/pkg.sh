# shellcheck shell=bash
# Distro-neutral package layer. Logical groups live in data/packages.tsv.

PKG_TABLE=${PKG_TABLE:-$TUX_SRC/data/packages.tsv}

pkg_col() { case $DISTRO in arch) echo 2 ;; debian) echo 3 ;; void) echo 4 ;; esac; }

# pkgs_for group... -> package names for this distro
pkgs_for() {
  local col g
  col=$(pkg_col)
  for g in "$@"; do
    awk -F'\t' -v g="$g" -v c="$col" '$1==g && $c!="-" {print $c}' "$PKG_TABLE"
  done | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' '
}

pkg_refresh() {
  case $DISTRO in
    arch)   run pacman -Sy --noconfirm ;;
    debian) run apt-get update ;;
    void)   run xbps-install -Sy xbps; run xbps-install -Sy ;;
  esac
}

pkg_available() {
  case $DISTRO in
    arch)   pacman -Si "$1" &>/dev/null || pacman -Sg "$1" &>/dev/null ;;
    debian) apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate: [^(]' ;;
    void)   xbps-query -R "$1" &>/dev/null ;;
  esac
}

pkg_installed() {
  case $DISTRO in
    arch)   pacman -Qq "$1" &>/dev/null ;;
    debian) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
    void)   xbps-query "$1" &>/dev/null ;;
  esac
}

PKG_MISSING=''

# pkg_install name... : installs what exists, records what does not
pkg_install() {
  local p want=()
  for p in "$@"; do
    if has_word "${TUX_EXCLUDE:-}" "$p"; then info "Skipping excluded package $p"; continue; fi
    if pkg_available "$p"; then want+=("$p"); else PKG_MISSING+=" $p"; warn "Package not available on $DISTRO: $p"; fi
  done
  ((${#want[@]})) || return 0
  info "Installing ${#want[@]} packages: ${want[*]}"
  case $DISTRO in
    arch)   run pacman -S --needed --noconfirm "${want[@]}" ;;
    debian) DEBIAN_FRONTEND=noninteractive run apt-get install -y "${want[@]}" ;;
    void)   run xbps-install -y "${want[@]}" ;;
  esac || {
    # One bad package should not sink the whole transaction: retry one by one.
    warn "Batch install failed, retrying packages individually (see $TUX_LOG)"
    for p in "${want[@]}"; do
      case $DISTRO in
        arch)   run pacman -S --needed --noconfirm "$p" ;;
        debian) DEBIAN_FRONTEND=noninteractive run apt-get install -y "$p" ;;
        void)   run xbps-install -y "$p" ;;
      esac || { PKG_MISSING+=" $p"; warn "Failed to install $p"; }
    done
  }
}

pkg_install_groups() {
  # shellcheck disable=SC2046
  pkg_install $(pkgs_for "$@")
}
