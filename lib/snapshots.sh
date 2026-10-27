# shellcheck shell=bash
# Btrfs safety net:
#   * snapper timeline snapshots of / and /home (automatic, self-pruning)
#   * pre/post snapshots around every package transaction
#   * every snapshot of / is bootable from the GRUB "snapshots" submenu (grub-btrfs)
#   * `tux-snap rollback N` restores a snapshot as the new root

root_is_btrfs() { [[ $(findmnt -no FSTYPE /) == btrfs ]]; }

snap_config() {  # snap_config name mountpoint
  local name=$1 mp=$2 snapdir="$2/.snapshots" was_mounted=0
  [[ -f /etc/snapper/configs/$name ]] && { info "snapper config '$name' exists"; return 0; }
  # Our layout mounts @snapshots at /.snapshots. snapper wants to create that subvolume
  # itself, so let it, then swap its nested subvolume for our dedicated one.
  if mountpoint -q "$snapdir"; then umount "$snapdir"; was_mounted=1; fi
  if [[ -d $snapdir ]]; then rmdir "$snapdir" 2>/dev/null || true; fi
  run snapper --no-dbus -c "$name" create-config "$mp" || { warn "snapper create-config $name failed"; return 1; }
  if ((was_mounted)); then
    run btrfs subvolume delete "$snapdir"
    mkdir -p "$snapdir"
    mount "$snapdir"
  fi
  chmod 750 "$snapdir"
  chown :wheel "$snapdir" 2>/dev/null || true
}

snapshots_stage() {
  root_is_btrfs || { warn "Root is not btrfs: skipping snapshots. (A fresh tuxcraft install always uses btrfs.)"; return 0; }
  step "Snapshots: snapper + grub-btrfs"
  pkg_install_groups snapshots

  snap_config root /
  # /home is its own subvolume: snapshots protect against "I deleted my thesis" moments.
  if [[ $(findmnt -no FSTYPE /home) == btrfs ]] && findmnt -no OPTIONS /home | grep -q subvol; then
    snap_config home /home
  fi

  local common=(ALLOW_GROUPS=wheel SYNC_ACL=yes NUMBER_CLEANUP=yes NUMBER_MIN_AGE=1800
                TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes TIMELINE_MIN_AGE=1800)
  [[ -f /etc/snapper/configs/root ]] && run snapper --no-dbus -c root set-config "${common[@]}" \
      NUMBER_LIMIT=20 NUMBER_LIMIT_IMPORTANT=10 \
      TIMELINE_LIMIT_HOURLY=8 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=4 \
      TIMELINE_LIMIT_MONTHLY=3 TIMELINE_LIMIT_YEARLY=0
  [[ -f /etc/snapper/configs/home ]] && run snapper --no-dbus -c home set-config "${common[@]}" \
      NUMBER_LIMIT=5 NUMBER_LIMIT_IMPORTANT=5 \
      TIMELINE_LIMIT_HOURLY=12 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=4 \
      TIMELINE_LIMIT_MONTHLY=3 TIMELINE_LIMIT_YEARLY=0

  # Scheduling
  if [[ $INIT == systemd ]]; then
    # snapper-boot: one snapshot of / per boot, so there is always a state from before today's changes.
    svc_enable snapper-timeline.timer snapper-cleanup.timer snapper-boot.timer
  else
    write_file /etc/cron.hourly/tuxcraft-snapper 755 <<'EOF'
#!/bin/sh
# snapper timeline + cleanup (Void has no systemd timers)
for c in root home; do
  [ -f "/etc/snapper/configs/$c" ] || continue
  snapper --no-dbus -c "$c" create -c timeline -d timeline
  snapper --no-dbus -c "$c" cleanup timeline
  snapper --no-dbus -c "$c" cleanup number
done
EOF
  fi

  # Pre/post snapshots around package operations
  case $DISTRO in
    arch) : ;;  # snap-pac does this for every pacman transaction
    debian)
      if ! grep -rqs snapper /etc/apt/apt.conf.d/; then
        write_file /etc/apt/apt.conf.d/80tuxcraft-snapper <<'EOF'
// Snapshot / before every dpkg run (tuxcraft)
DPkg::Pre-Invoke  { "if [ -x /usr/bin/snapper ] && [ -e /etc/snapper/configs/root ]; then snapper --no-dbus -c root create -c number -d 'apt (pre)' || true; fi"; };
DPkg::Post-Invoke { "if [ -x /usr/bin/snapper ] && [ -e /etc/snapper/configs/root ]; then snapper --no-dbus -c root create -c number -d 'apt (post)' || true; fi"; };
EOF
      fi ;;
    void) : ;;  # xbps has no hooks: `sysup` takes the pre/post snapshots
  esac

  # Bootable snapshots in GRUB
  if ! pkg_installed grub-btrfs && [[ ! -f /etc/grub.d/41_snapshots-btrfs ]]; then
    info "grub-btrfs not packaged here, installing from source"
    local tmp; tmp=$(mktemp -d)
    if run git clone --depth 1 https://github.com/Antynea/grub-btrfs "$tmp/grub-btrfs"; then
      run make -C "$tmp/grub-btrfs" install || warn "grub-btrfs install failed"
    fi
    rm -rf "$tmp"
  fi
  if [[ -f /etc/default/grub-btrfs/config ]]; then
    sed -i 's|^#\?GRUB_BTRFS_SUBMENUNAME=.*|GRUB_BTRFS_SUBMENUNAME="tuxcraft snapshots (read-only, run tux-snap rollback)"|' /etc/default/grub-btrfs/config
    # Debian names it update-grub/grub-mkconfig in /usr/sbin; grub-btrfs autodetects otherwise.
  fi
  if [[ $INIT == systemd ]]; then
    svc_enable grub-btrfsd.service
  else
    svc_enable grub-btrfs
  fi
  ok "Snapshots configured: hourly timeline + pre/post package snapshots + GRUB entries"
}

# A known-good baseline to roll back to, taken once everything is installed.
snapshots_baseline() {
  [[ -f /etc/snapper/configs/root ]] || return 0
  run snapper --no-dbus -c root create -c number -u important=yes -d "tuxcraft: fresh setup" || true
}
