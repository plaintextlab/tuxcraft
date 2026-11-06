# shellcheck shell=bash
# Where to install (whole disk, free space, an existing partition), optional LUKS encryption,
# and the btrfs subvolume layout.
#
# Whole disk (GPT):
#   UEFI: p1 1 GiB EFI (FAT32, /boot/efi)   p2 rest: btrfs, or LUKS2 holding btrfs
#   BIOS: p1 1 MiB bios_grub                 p2 rest: same
# Free space / existing partition (UEFI only, for dual boot): one new or reused partition for
# btrfs (or LUKS2), and the EFI system partition that is already there, mounted, never formatted.
#
# Subvolumes (flat layout, every one mounted explicitly):
#   @            /            rolled back as a unit
#   @home        /home        never touched by a root rollback
#   @snapshots   /.snapshots  snapper snapshots of @, survives rollbacks
#   @var_log     /var/log     keep logs across rollbacks (you want to see what broke)
#   @var_cache   /var/cache   package caches do not belong in snapshots
#   @var_tmp     /var/tmp
# /boot lives inside @ on purpose: kernel + modules always match the snapshot you boot. With
# encryption that means GRUB itself unlocks the disk (LUKS2 with PBKDF2, which GRUB can read),
# and a key file inside the encrypted root lets the initramfs open it again without a second
# passphrase prompt.

BTRFS_OPTS='noatime,compress=zstd:1,space_cache=v2'
TARGET=/mnt
ESP_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
MIN_BYTES=$((20 * 1024 * 1024 * 1024))   # 20 GiB: base system, desktop and room for snapshots
CRYPT_NAME=cryptroot
CRYPT_KEY=/etc/cryptsetup-keys.d/cryptroot.key

part_path() {  # part_path /dev/nvme0n1 2 -> /dev/nvme0n1p2
  if [[ $1 =~ [0-9]$ ]]; then echo "${1}p$2"; else echo "${1}$2"; fi
}

human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1 B"; }

# Disk that holds the running live system, never offered as a target.
live_disk() {
  local src m
  for m in /run/archiso/bootmnt /run/live/medium /run/initramfs/live; do
    src=$(findmnt -no SOURCE "$m" 2>/dev/null) || continue
    [[ -n $src ]] && { lsblk -npo PKNAME "$src" 2>/dev/null | head -n1; return; }
  done
}

# EFI system partitions on any disk except the live one.
find_esps() {
  local skip name type pk
  skip=$(live_disk || true)
  while read -r name type pk; do
    [[ ${type,,} == "$ESP_TYPE" && $pk != "$skip" ]] && echo "$name"
  done < <(lsblk -lnpo NAME,PARTTYPE,PKNAME)
  return 0
}

# Largest unpartitioned area of a GPT disk: "start_sector bytes" (nothing if not GPT).
largest_free() {
  local ss
  sfdisk -d "$1" 2>/dev/null | grep -q '^label: gpt' || return 0
  ss=$(blockdev --getss "$1" 2>/dev/null || echo 512)
  sfdisk -F "$1" 2>/dev/null | awk -v ss="$ss" '
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { if ($3 > best) { best = $3; start = $1 } }
    END { if (best) printf "%s %.0f\n", start, best * ss }'
}

pick_target() {
  local -a opts=("disk|Erase a whole disk|simplest; everything on that disk is deleted")
  if [[ $BOOT_MODE == uefi ]]; then
    opts+=("free|Use free space on a disk|keeps Windows / other systems (dual boot)"
           "part|Replace one partition|reformat a partition you choose; the rest stays")
  fi
  choose TUX_TARGET "Where should $DISTRO go?" disk "${opts[@]}"
  if [[ $TUX_TARGET != disk ]]; then
    [[ $BOOT_MODE == uefi ]] || die "Dual boot (free space / partition) needs UEFI. Use TUX_TARGET=disk."
    [[ -n $(find_esps) ]] || die "No EFI system partition found to share. Erase a whole disk instead (TUX_TARGET=disk)."
  fi
  case $TUX_TARGET in
    disk) pick_disk ;;
    free) pick_free ;;
    part) pick_part ;;
    *) die "TUX_TARGET must be disk, free or part (got '$TUX_TARGET')" ;;
  esac
}

pick_disk() {
  local -a opts=()
  local name size model tran skip
  skip=$(live_disk || true)
  while read -r name size tran model; do
    [[ $name == "$skip" ]] && continue
    opts+=("$name|$name  $size|${tran:-?} ${model:-}")
  done < <(lsblk -dnpo NAME,SIZE,TRAN,MODEL -e 7,11,251 | awk '$2 != "0B"')
  ((${#opts[@]})) || die "No installable disk found."
  echo
  lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS -e 7,11 || true
  choose TUX_DISK "Which disk should tuxcraft ERASE and install to?" "${opts[0]%%|*}" "${opts[@]}"
  [[ -b $TUX_DISK ]] || die "$TUX_DISK is not a block device"
}

pick_free() {
  local -a opts=()
  local name size model skip free bytes
  skip=$(live_disk || true)
  while read -r name size model; do
    [[ $name == "$skip" ]] && continue
    free=$(largest_free "$name")
    [[ -n $free ]] || continue
    bytes=${free#* }
    ((bytes >= MIN_BYTES)) || continue
    opts+=("$name|$name  $(human "$bytes") free|of $size ${model:-}")
  done < <(lsblk -dnpo NAME,SIZE,MODEL -e 7,11,251 | awk '$2 != "0B"')
  ((${#opts[@]})) || die "No GPT disk with at least $(human $MIN_BYTES) of free space. Shrink a partition first (Windows: Disk Management > Shrink Volume)."
  choose TUX_DISK "Install into the free space of which disk? (existing partitions are kept)" "${opts[0]%%|*}" "${opts[@]}"
  [[ -b $TUX_DISK ]] || die "$TUX_DISK is not a block device"
}

pick_part() {
  local -a opts=()
  local line skip re
  skip=$(live_disk || true)
  # -P: one KEY="value" line per device; empty columns stay in place (unlike the table output).
  re='^NAME="([^"]*)" SIZE="([^"]*)" TYPE="([^"]*)" FSTYPE="([^"]*)" PARTTYPE="([^"]*)" PKNAME="([^"]*)" MOUNTPOINT="([^"]*)" LABEL="([^"]*)"'
  while IFS= read -r line; do
    [[ $line =~ $re ]] || continue
    local name=${BASH_REMATCH[1]} size=${BASH_REMATCH[2]} type=${BASH_REMATCH[3]} fstype=${BASH_REMATCH[4]}
    local ptype=${BASH_REMATCH[5]} pk=${BASH_REMATCH[6]} mnt=${BASH_REMATCH[7]} label=${BASH_REMATCH[8]}
    [[ $type == part && $pk != "$skip" && ${ptype,,} != "$ESP_TYPE" && -z $mnt ]] || continue
    ((size >= MIN_BYTES)) || continue
    opts+=("$name|$name  $(human "$size")|${fstype:-empty} ${label}")
  done < <(lsblk -Pbpo NAME,SIZE,TYPE,FSTYPE,PARTTYPE,PKNAME,MOUNTPOINT,LABEL)
  ((${#opts[@]})) || die "No partition of at least $(human $MIN_BYTES) that is free to replace."
  echo
  lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS -e 7,11 || true
  choose TUX_PART "Which partition should be ERASED for $DISTRO?" "${opts[0]%%|*}" "${opts[@]}"
  [[ -b $TUX_PART ]] || die "$TUX_PART is not a block device"
  case $(lsblk -dno FSTYPE "$TUX_PART") in
    ntfs|BitLocker) warn "$TUX_PART looks like a Windows partition. Make sure it is the one you mean." ;;
  esac
}

pick_encryption() {
  # On by default when asked; off for unattended runs that do not say (older answers files).
  local def=yes
  [[ -n ${TUX_YES:-} ]] && def=no
  choose TUX_ENCRYPT "Encrypt the disk (LUKS2)?" "$def" \
    "yes|Yes, encrypt|a passphrase at power-on protects everything if the laptop is lost" \
    "no|No|boots without a passphrase"
  [[ $TUX_ENCRYPT == yes ]] || return 0
  if [[ -z ${TUX_LUKS_PASSWORD:-} ]]; then
    if [[ -n ${TUX_YES:-} ]]; then
      TUX_LUKS_PASSWORD=${TUX_PASSWORD:-}
      [[ -n $TUX_LUKS_PASSWORD ]] || die "TUX_LUKS_PASSWORD (or TUX_PASSWORD) must be set for unattended encrypted installs"
    else
      info "The passphrase is typed in GRUB before anything else loads, with a US keyboard layout."
      ask_secret TUX_LUKS_PASSWORD "Disk encryption passphrase"
    fi
  fi
  ((${#TUX_LUKS_PASSWORD} >= 8)) || warn "A passphrase shorter than 8 characters is easy to guess."
  return 0
}

target_summary() {
  case $TUX_TARGET in
    disk) echo "$TUX_DISK (whole disk ERASED)" ;;
    free) echo "free space on $TUX_DISK (other partitions kept)" ;;
    part) echo "$TUX_PART (this partition ERASED, the rest kept)" ;;
  esac
}

confirm_wipe() {
  [[ -n ${TUX_YES:-} && -n ${TUX_WIPE_CONFIRMED:-} ]] && return 0
  local dev=$TUX_DISK what="ALL DATA ON $TUX_DISK"
  case $TUX_TARGET in
    free) confirm "Create a new partition in the free space of $TUX_DISK?" y || die "Aborted, nothing was changed."; return 0 ;;
    part) dev=$TUX_PART what="ALL DATA ON THE PARTITION $TUX_PART" ;;
  esac
  printf '\n%s%s WILL BE DESTROYED.%s\n' "$C_RED$C_BOLD" "$what" "$C_RESET"
  local ans
  read -r -p "Type the name ($(basename "$dev")) to continue: " ans </dev/tty
  [[ $ans == "$(basename "$dev")" ]] || die "Aborted, nothing was changed."
}

# Leftovers of an earlier, interrupted run.
release_target() {
  swapoff -a 2>/dev/null || true
  umount -R "$TARGET" 2>/dev/null || true
  [[ -e /dev/mapper/$CRYPT_NAME ]] && { cryptsetup close "$CRYPT_NAME" 2>/dev/null || warn "Could not close an old /dev/mapper/$CRYPT_NAME"; }
  return 0
}

_parts_of() { lsblk -lnpo NAME "$1" | tail -n +2 | sort; }

disk_partition() {
  case $TUX_TARGET in
    disk)
      local p
      for p in $(_parts_of "$TUX_DISK"); do umount -f "$p" 2>/dev/null || true; done
      run wipefs -af "$TUX_DISK"
      if [[ $BOOT_MODE == uefi ]]; then
        printf 'label: gpt\nsize=1GiB, type=U, name="EFI"\ntype=L, name="tuxcraft"\n' | run sfdisk --wipe always "$TUX_DISK"
      else
        printf 'label: gpt\nsize=1MiB, type=21686148-6449-6E6F-744E-656564454649, name="BIOS"\ntype=L, name="tuxcraft"\n' | run sfdisk --wipe always "$TUX_DISK"
      fi
      run partprobe "$TUX_DISK" || true
      udevadm settle 2>/dev/null || sleep 2
      PART_EFI=$(part_path "$TUX_DISK" 1)
      PART_ROOT=$(part_path "$TUX_DISK" 2)
      FORMAT_EFI=1
      ;;
    free)
      local before after start
      start=$(largest_free "$TUX_DISK"); start=${start%% *}
      [[ -n $start ]] || die "No free space found on $TUX_DISK any more"
      before=$(_parts_of "$TUX_DISK")
      printf 'start=%s, type=L, name="tuxcraft"\n' "$start" | run sfdisk --append --no-reread "$TUX_DISK"
      run partprobe "$TUX_DISK" || true
      udevadm settle 2>/dev/null || sleep 2
      after=$(_parts_of "$TUX_DISK")
      PART_ROOT=$(comm -13 <(echo "$before") <(echo "$after") | head -n1)
      [[ -b $PART_ROOT ]] || die "The new partition on $TUX_DISK did not appear (reboot and try again)"
      PART_EFI=$(pick_esp "$TUX_DISK")
      FORMAT_EFI=0
      ;;
    part)
      PART_ROOT=$(readlink -f "$TUX_PART")
      run wipefs -af "$PART_ROOT"
      PART_EFI=$(pick_esp "$(lsblk -npo PKNAME "$PART_ROOT" | head -n1)")
      FORMAT_EFI=0
      ;;
  esac
  ok "Partitions: root $PART_ROOT${PART_EFI:+, EFI $PART_EFI}$( ((FORMAT_EFI)) || echo ' (shared, not formatted)')"
}

# The EFI partition to share: one on the same disk if there is one, else the first found.
pick_esp() {
  local esps e
  esps=$(find_esps)
  for e in $esps; do [[ $(lsblk -npo PKNAME "$e" | head -n1) == "$1" ]] && { echo "$e"; return; }; done
  e=${esps%%$'\n'*}
  [[ -n $e ]] || die "No EFI system partition found"
  echo "$e"
}

luks_setup() {
  step "Encrypting $PART_ROOT (LUKS2)"
  command -v cryptsetup >/dev/null || die "cryptsetup missing on the live system"
  # PBKDF2, not the argon2id default: GRUB can only unlock PBKDF2 key slots.
  printf '%s' "$TUX_LUKS_PASSWORD" | run cryptsetup luksFormat --batch-mode --type luks2 \
    --pbkdf pbkdf2 --hash sha512 --iter-time 1000 --key-file=- "$PART_ROOT" || die "luksFormat failed"
  printf '%s' "$TUX_LUKS_PASSWORD" | run cryptsetup open --allow-discards --key-file=- "$PART_ROOT" "$CRYPT_NAME" ||
    die "Could not open the encrypted partition"
  ROOT_DEV=/dev/mapper/$CRYPT_NAME
}

# Random key file inside the encrypted root, so the initramfs does not ask a second time.
# Low iteration count is fine: 2 KiB of random data cannot be guessed, and GRUB tries every
# slot with the passphrase, so a slow second slot would only slow down every boot.
luks_keyfile() {
  local kf=$TARGET$CRYPT_KEY
  install -d -m700 "$(dirname "$kf")"
  (umask 077; dd if=/dev/urandom of="$kf" bs=512 count=4 status=none)
  printf '%s' "$TUX_LUKS_PASSWORD" | run cryptsetup luksAddKey --batch-mode --pbkdf pbkdf2 \
    --pbkdf-force-iterations 1000 --key-file=- "$PART_ROOT" "$kf" || die "Could not add the key file"
}

disk_prepare() {
  # A stable /dev/disk/by-id name is safest in an answers file (nvme0/nvme1 can swap between
  # boots), but partition names are derived from the kernel name.
  [[ -n ${TUX_DISK:-} ]] && TUX_DISK=$(readlink -f "$TUX_DISK")
  step "Preparing the disk ($(target_summary), $BOOT_MODE)"
  release_target
  disk_partition

  [[ ${FORMAT_EFI:-0} == 1 && $BOOT_MODE == uefi ]] && run mkfs.fat -F32 -n EFI "$PART_EFI"
  ROOT_DEV=$PART_ROOT
  [[ ${TUX_ENCRYPT:-no} == yes ]] && luks_setup
  run mkfs.btrfs -f -L tuxcraft "$ROOT_DEV"

  step "Creating btrfs subvolumes"
  mount "$ROOT_DEV" "$TARGET"
  local sv
  for sv in @ @home @snapshots @var_log @var_cache @var_tmp; do
    run btrfs subvolume create "$TARGET/$sv"
  done
  umount "$TARGET"

  mount -o "$BTRFS_OPTS,subvol=@" "$ROOT_DEV" "$TARGET"
  mkdir -p "$TARGET"/{home,.snapshots,var/log,var/cache,var/tmp,boot}
  mount -o "$BTRFS_OPTS,subvol=@home"      "$ROOT_DEV" "$TARGET/home"
  mount -o "$BTRFS_OPTS,subvol=@snapshots" "$ROOT_DEV" "$TARGET/.snapshots"
  mount -o "$BTRFS_OPTS,subvol=@var_log"   "$ROOT_DEV" "$TARGET/var/log"
  mount -o "$BTRFS_OPTS,subvol=@var_cache" "$ROOT_DEV" "$TARGET/var/cache"
  mount -o "$BTRFS_OPTS,subvol=@var_tmp"   "$ROOT_DEV" "$TARGET/var/tmp"
  chmod 1777 "$TARGET/var/tmp"
  if [[ $BOOT_MODE == uefi ]]; then
    mkdir -p "$TARGET/boot/efi"
    mount "$PART_EFI" "$TARGET/boot/efi"
  fi
  [[ ${TUX_ENCRYPT:-no} == yes ]] && luks_keyfile
  write_disk_conf
  ok "Disk ready"
}

# What the stage inside the new system needs to know about the disk (no secrets).
write_disk_conf() {
  local luks_uuid=''
  [[ ${TUX_ENCRYPT:-no} == yes ]] && luks_uuid=$(blkid -s UUID -o value "$PART_ROOT")
  mkdir -p "$TARGET$TUX_ETC"
  {
    echo "# tuxcraft: disk layout written at install time"
    printf 'TUX_ROOT_PART=%q\n' "$PART_ROOT"
    printf 'TUX_LUKS_UUID=%q\n' "$luks_uuid"
    printf 'TUX_DUALBOOT=%q\n' "$([[ $TUX_TARGET == disk ]] && echo 0 || echo 1)"
  } >"$TARGET$TUX_ETC/disk.conf"
}

write_fstab() {
  local uuid euuid
  uuid=$(blkid -s UUID -o value "$ROOT_DEV")
  mkdir -p "$TARGET/etc"
  {
    echo "# <device> <mountpoint> <type> <options> <dump> <pass>   (generated by tuxcraft)"
    echo "UUID=$uuid  /            btrfs  $BTRFS_OPTS,subvol=/@            0 0"
    echo "UUID=$uuid  /home        btrfs  $BTRFS_OPTS,subvol=/@home        0 0"
    echo "UUID=$uuid  /.snapshots  btrfs  $BTRFS_OPTS,subvol=/@snapshots   0 0"
    echo "UUID=$uuid  /var/log     btrfs  $BTRFS_OPTS,subvol=/@var_log     0 0"
    echo "UUID=$uuid  /var/cache   btrfs  $BTRFS_OPTS,subvol=/@var_cache   0 0"
    echo "UUID=$uuid  /var/tmp     btrfs  $BTRFS_OPTS,subvol=/@var_tmp     0 0"
    if [[ $BOOT_MODE == uefi ]]; then
      euuid=$(blkid -s UUID -o value "$PART_EFI")
      echo "UUID=$euuid  /boot/efi  vfat  umask=0077  0 2"
    fi
    echo "tmpfs  /tmp  tmpfs  defaults,nosuid,nodev  0 0"
  } >"$TARGET/etc/fstab"
}
