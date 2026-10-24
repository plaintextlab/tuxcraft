#!/usr/bin/env bash
# vm-check.sh — verify a finished tuxcraft install. Run as the desktop user, inside the
# installed system (works on real hardware too):
#     curl -fsSL 10.0.2.2:8000/check | bash        # from a tests/vm-test.sh VM
#     bash tests/vm-check.sh                       # from a checkout
# Prints PASS / WARN / FAIL per item and exits 1 if anything failed.
set -uo pipefail

g=$'\e[32m' y=$'\e[33m' r=$'\e[31m' b=$'\e[1m' n=$'\e[0m'
pass=0 warn=0 fail=0
ok()   { printf ' %sPASS%s %s\n' "$g" "$n" "$1"; pass=$((pass+1)); }
wn()   { printf ' %sWARN%s %s\n' "$y" "$n" "$1"; warn=$((warn+1)); }
bad()  { printf ' %sFAIL%s %s\n' "$r" "$n" "$1"; fail=$((fail+1)); }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
section() { printf '\n%s%s%s\n' "$b" "$1" "$n"; }

[[ $EUID -eq 0 ]] && { echo "Run this as the desktop user, not root (it uses sudo where needed)."; exit 1; }
SUDO=sudo; sudo -n true 2>/dev/null || { echo "sudo will ask for your password (tux in test VMs)"; }

# shellcheck source=/dev/null
. /etc/tuxcraft/session.conf 2>/dev/null || true
# shellcheck source=/dev/null
. "$HOME/.config/tuxcraft/state" 2>/dev/null || true
SESSION=${SESSION:-i3}
if [[ -d /run/systemd/system ]]; then INIT=systemd; else INIT=runit; fi
enabled() {
  if [[ $INIT == systemd ]]; then systemctl is-enabled "$1"; else [[ -L /etc/runit/runsvdir/default/$1 ]]; fi
}
active() {
  if [[ $INIT == systemd ]]; then systemctl is-active "$1"; else $SUDO sv status "$1" | grep -q '^run:'; fi
}

section "tuxcraft"
check "session.conf present (${DISTRO:-?}, $SESSION)" test -f /etc/tuxcraft/session.conf
check "answers.conf saved" $SUDO test -f /etc/tuxcraft/answers.conf
check "user state file (theme ${THEME:-?}, font ${FONT:-?})" test -f "$HOME/.config/tuxcraft/state"
for c in tux-theme tux-theme-system tux-font tux-session tux-autostart tux-snap tux-backup sysup tux-menu tux-lock tux-control; do
  command -v "$c" >/dev/null || bad "command $c missing"
done
ok "tux-* commands checked"
log=/var/log/tuxcraft.log
if $SUDO test -f $log; then
  ok "install log present"
  missing=$($SUDO grep -h 'Package not available\|Failed to install' $log | sed 's/.*: //' | sort -u | tr '\n' ' ')
  [[ -n $missing ]] && wn "packages skipped during install: $missing"
  errs=$($SUDO grep -c '^.\{19\} FATAL' $log)
  [[ $errs -gt 0 ]] && bad "install log contains $errs FATAL line(s)"
else
  bad "install log /var/log/tuxcraft.log missing"
fi

section "Disk & snapshots"
if [[ $(findmnt -no FSTYPE /) == btrfs ]]; then
  ok "root is btrfs ($(findmnt -no OPTIONS / | grep -o 'compress=[^,]*'))"
  for m in /home /.snapshots /var/log /var/cache /var/tmp; do
    check "$m is its own subvolume" findmnt -n "$m"
  done
  check "snapper config: root" test -f /etc/snapper/configs/root
  check "snapper config: home" test -f /etc/snapper/configs/home
  if $SUDO snapper --no-dbus -c root list 2>/dev/null | grep -q 'tuxcraft: fresh setup'; then ok "baseline snapshot exists"; else bad "baseline snapshot missing"; fi
  if [[ $INIT == systemd ]]; then
    check "snapper-timeline.timer enabled" enabled snapper-timeline.timer
    check "snapper-cleanup.timer enabled" enabled snapper-cleanup.timer
    check "grub-btrfsd enabled" enabled grub-btrfsd.service
  else
    check "hourly snapper cron job" test -x /etc/cron.hourly/tuxcraft-snapper
    check "cronie enabled" enabled cronie
    check "grub-btrfs service enabled" enabled grub-btrfs
  fi
  check "grub-btrfs installed" test -f /etc/grub.d/41_snapshots-btrfs
  case ${DISTRO:-} in
    arch)   check "snap-pac installed (pacman pre/post snapshots)" pacman -Q snap-pac ;;
    debian) check "apt snapshot hook" bash -c 'grep -rqs snapper /etc/apt/apt.conf.d/' ;;
  esac
  before=$($SUDO snapper --no-dbus -c root list 2>/dev/null | wc -l)
  $SUDO tux-snap create "vm-check" >/dev/null 2>&1
  after=$($SUDO snapper --no-dbus -c root list 2>/dev/null | wc -l)
  ((after > before)) && ok "tux-snap create works" || bad "tux-snap create did not add a snapshot"
else
  wn "root is not btrfs: snapshot checks skipped"
fi
check "zram swap active" bash -c 'swapon --show=NAME --noheadings | grep -q zram'

section "Boot"
check "GRUB config present" $SUDO test -f /boot/grub/grub.cfg
if [[ ${DISTRO:-} == arch ]]; then
  check "fallback kernel linux-lts installed" pacman -Q linux-lts
fi

section "Services"
check "NetworkManager enabled" enabled NetworkManager
check "NetworkManager running" active NetworkManager
check "network reachable" bash -c 'curl -fsI --max-time 8 https://github.com || ping -c1 -W3 1.1.1.1'
if command -v tuigreet >/dev/null; then
  check "greetd enabled" enabled greetd
  check "greetd uses tuigreet + tux-session" grep -q 'tuigreet.*--cmd tux-session' /etc/greetd/config.toml
else
  wn "tuigreet not installed (LightDM fallback)"
  check "lightdm enabled" enabled lightdm
fi
check "console palette written" test -f /etc/tuxcraft/vtrgb
[[ $INIT == runit ]] && { check "dbus enabled" enabled dbus; check "elogind enabled" enabled elogind; }

section "Desktop ($SESSION)"
if [[ $SESSION == sway ]]; then apps=(sway waybar fuzzel swaylock swayidle swaybg grim slurp wl-copy cliphist)
else apps=(i3 polybar rofi picom feh i3lock xss-lock maim xclip startx xsettingsd); fi
apps+=(alacritty dunst nm-applet udiskie imv mpv playerctl gammastep pactl wpctl)
for a in "${apps[@]}"; do command -v "$a" >/dev/null || bad "missing: $a"; done
ok "session programs checked"
check "polkit agent found" bash -c 'grep -o "/usr/[^ ]*polkit[^ ]*agent-1" /usr/local/bin/tux-polkit | while read -r p; do [ -x "$p" ] && exit 0; done; exit 1'
if [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
  ok "running inside a graphical session"
  for p in dunst; do check "$p running" pgrep -x "$p"; done
  if [[ $SESSION == sway ]]; then check "waybar running" pgrep -x waybar; else check "polybar running" pgrep -x polybar; fi
  check "pipewire running" pgrep -x pipewire
  check "audio server answers (pactl)" pactl info
else
  wn "not in a graphical session: run this from a terminal on the desktop to check the live session too"
fi

section "TUI apps"
for a in yazi btop lazygit nmtui fzf bat eza fd rg zoxide starship micro fastfetch ncdu qalc; do
  command -v "$a" >/dev/null || bad "missing: $a"
done
ok "TUI apps checked"
command -v bluetui >/dev/null || wn "bluetui missing"
command -v wiremix >/dev/null || command -v pulsemixer >/dev/null || bad "no TUI mixer"

section "Theme & fonts"
tdir="$HOME/.config"
left=$(grep -rl '{{' "$tdir/i3" "$tdir/sway" "$tdir/polybar" "$tdir/waybar" "$tdir/rofi" "$tdir/fuzzel" "$tdir/dunst" \
       "$tdir/alacritty" "$tdir/gtk-3.0" "$tdir/gtk-4.0" "$tdir/qt5ct" "$tdir/qt6ct" "$tdir/starship.toml" 2>/dev/null)
[[ -z $left ]] && ok "all templates rendered" || bad "unrendered placeholders in: $left"
check "GTK3 theme adw-gtk3 installed" bash -c 'ls -d /usr/share/themes/adw-gtk3* ~/.local/share/themes/adw-gtk3* 2>/dev/null | grep -q .'
check "Papirus icons installed" test -d /usr/share/icons/Papirus-Dark
check "Qt palette (qt6ct)" test -f "$tdir/qt6ct/colors/tuxcraft.conf"
check "QT_QPA_PLATFORMTHEME set by tux-session" grep -q 'QT_QPA_PLATFORMTHEME=qt5ct' /usr/local/bin/tux-session
check "font '${FONT:-?}' known to fontconfig" bash -c "fc-list : family | grep -qF \"${FONT:-JetBrainsMono Nerd Font}\""
check "Symbols Nerd Font installed" bash -c 'fc-list : family | grep -q "Symbols Nerd Font"'
check "theme switch round-trip" bash -c 'cur=$(tux-theme current); TUX_NO_RELOAD=1 tux-theme set nord && grep -q 2e3440 ~/.config/alacritty/theme.toml && TUX_NO_RELOAD=1 tux-theme set "$cur"'

section "Updates"
check "sysup present" test -x /usr/local/bin/sysup
case ${DISTRO:-} in
  arch)   check "paccache timer enabled" enabled paccache.timer ;;
  debian) check "unattended security upgrades configured" test -f /etc/apt/apt.conf.d/20auto-upgrades ;;
esac

printf '\n%s%d passed, %d warnings, %d failed%s\n' "$b" "$pass" "$warn" "$fail" "$n"
((fail == 0))
