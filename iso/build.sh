#!/usr/bin/env bash
# iso/build.sh — build the tuxcraft live ISO (Arch-based; installs Arch, Debian or Void).
#
#   sudo iso/build.sh [OUTDIR]          on Arch, with: pacman -S archiso
#   CI: .github/workflows/iso.yml        (archlinux container, --privileged)
#
# Starts from Arch's own "releng" profile (the official install ISO), so boot loaders, firmware
# and hardware support stay exactly Arch's; this only adds packages, a copy of this checkout in
# /usr/share/tuxcraft, and the tuxcraft-live launcher that starts on tty1 by itself.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
OUT=${1:-$REPO/iso/out}
WORK=${WORK:-/tmp/tuxcraft-iso-work}
VERSION=${TUX_VERSION:-$(git -C "$REPO" describe --tags --always 2>/dev/null || date +%Y.%m.%d)}

[[ $EUID -eq 0 ]] || { echo "Run as root (mkarchiso needs it)" >&2; exit 1; }
command -v mkarchiso >/dev/null || { echo "Install archiso first: pacman -S archiso" >&2; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK" "$OUT"
PROFILE=$WORK/profile
cp -r /usr/share/archiso/configs/releng "$PROFILE"

# Packages: releng's list plus what installing Debian and Void needs from an Arch host.
grep -v '^#' "$HERE/packages.extra" | sed '/^$/d' >>"$PROFILE/packages.x86_64"
sort -u -o "$PROFILE/packages.x86_64" "$PROFILE/packages.x86_64"

# Files: the launcher, autostart on tty1, and tuxcraft itself (this checkout, as it is).
cp -rT "$HERE/airootfs" "$PROFILE/airootfs"
mkdir -p "$PROFILE/airootfs/usr/share/tuxcraft"
tar -C "$REPO" --exclude=.git --exclude=tests/.vm --exclude=iso/out -cf - . | tar -C "$PROFILE/airootfs/usr/share/tuxcraft" -xf -
echo "$VERSION" >"$PROFILE/airootfs/etc/tuxcraft-iso"

# Name, label and boot menu titles.
sed -i -E \
  -e "s|^iso_name=.*|iso_name=\"tuxcraft\"|" \
  -e "s|^iso_label=.*|iso_label=\"TUXCRAFT_\$(date --date=\"@\${SOURCE_DATE_EPOCH:-\$(date +%s)}\" +%Y%m)\"|" \
  -e "s|^iso_publisher=.*|iso_publisher=\"PlainTextLab <https://github.com/plaintextlab/tuxcraft>\"|" \
  -e "s|^iso_application=.*|iso_application=\"tuxcraft installer: Arch, Debian or Void\"|" \
  -e "s|^iso_version=.*|iso_version=\"${VERSION#v}\"|" \
  -e 's|^file_permissions=\(|file_permissions=(\n  ["/usr/local/bin/tuxcraft-live"]="0:0:755"\n  ["/usr/local/bin/tux-wifi-live"]="0:0:755"|' \
  "$PROFILE/profiledef.sh"
grep -rlZ 'Arch Linux install medium' "$PROFILE"/{efiboot,grub,syslinux} 2>/dev/null |
  xargs -0 -r sed -i 's/Arch Linux install medium/tuxcraft installer/g'

mkarchiso -v -r -w "$WORK/build" -o "$OUT" "$PROFILE"
cd "$OUT"
for iso in tuxcraft-*.iso; do sha256sum "$iso" >"$iso.sha256"; done
ls -lh "$OUT"
