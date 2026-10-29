# tuxcraft

One script from a live ISO to a complete, themed, keyboard-driven Linux desktop —
**i3 (X11) or sway (Wayland)** on **Arch, Debian or Void**, with btrfs snapshots that
make a bad update a two-minute fix instead of a reinstall.

It asks a handful of questions, then does everything else: partitioning, base system,
drivers, desktop, TUI apps, fonts, colours, login screen, snapshots and a safe update command.
Configs come from [debi3n](https://github.com/plaintextlab/debi3n), cleaned up and made
distro-neutral.

## Quick start

Boot the live ISO of the distro you want, connect to the internet, then:

```sh
curl -fsSL https://raw.githubusercontent.com/plaintextlab/tuxcraft/main/install.sh | sudo bash
```

| Distro | Boot this | Notes |
|---|---|---|
| Arch | official `archlinux-*.iso` | Wi-Fi: `iwctl` |
| Debian | a **live** ISO (`debian-live-13-*-standard.iso`) — the netinst image has no shell to run scripts | installs the same release as the ISO |
| Void | `void-live-x86_64-*-base.iso` (glibc recommended; NVIDIA needs glibc) | Wi-Fi: `nmtui` or `wpa_supplicant`. The ISO has no curl: first run `xbps-install -Syu xbps && xbps-install -y curl` |

Already have a minimal install (e.g. Debian from the normal installer)? Run the same
command there: tuxcraft detects that it is not on a live ISO and only sets up the desktop
(snapshots are added too if `/` is btrfs).

## What it asks

1. **Disk** to erase (live ISO only), computer name, user, password, timezone, keyboard
2. **X11 + i3** or **Wayland + sway** — same keys, same look either way
3. **NVIDIA proprietary driver?** (only asked when an NVIDIA GPU is detected; Intel/AMD just work)
4. **Colour scheme** — Gruvbox, Everforest, Catppuccin Mocha/Latte, Nord, Tokyo Night, Rosé Pine, Kanagawa, Dracula, Motif
5. **Font** (previews below) and size
6. **Browser** and **optional extras** (firewall, Flatpak, wallpapers, Bluetooth, music, printing, dev tools, office, gaming, paru).
   *Gaming* = Steam, gamemode, MangoHud, Heroic (Flatpak), plus the limits Proton needs (`vm.max_map_count`,
   open files); on Void also gamescope, Wine, winetricks, protontricks, vkBasalt and the 32-bit libraries.
   With the NVIDIA driver, the matching Flatpak GL runtime is installed so Flatpak games use the GPU.
7. Extra packages to **add**, packages to **leave out**

Answers are saved to `/etc/tuxcraft/answers.conf` (without the password); reuse them for an
identical machine with `sudo ./install.sh --config answers.conf --yes`.

## Fonts

![font previews](assets/font-previews/all.png)

Every choice gets Nerd Font icons through a fallback, so the bar and launcher look right even
with the DOS font. Change any time with **Super+Ctrl+F** or `tux-font set dos 13`.

## What you get

| Area | X11 session | Wayland session |
|---|---|---|
| Window manager | i3 | sway |
| Bar | polybar | waybar |
| Launcher / menus | rofi | fuzzel |
| Compositor | picom (v12 rules, animations) | built in |
| Lock / idle | i3lock + xss-lock | swaylock + swayidle |
| Wallpaper | feh | swaybg |
| Clipboard history | CopyQ | cliphist |
| Screenshots / recording | maim, ffmpeg | grim, slurp, wf-recorder |
| Monitors | autorandr / arandr | kanshi |

Shared by both: **Alacritty**, dunst, PipeWire, NetworkManager, polkit agent, gnome-keyring,
udiskie, gammastep (night light), xdg portals, Papirus icons, adw-gtk3.

**Login screen:** greetd + **tuigreet** — a TUI login that fits a keyboard-driven setup, works with
X11 and Wayland, systemd and runit, and is coloured by the system theme (the console palette is
themed too). LightDM is used only if tuigreet is not packaged.

**Files:** Thunar (right-click → Open Terminal Here opens alacritty), yazi in the terminal.
**TUI apps:** yazi (files), btop, lazygit, nmtui, bluetui, wiremix/pulsemixer, ncdu, micro + neovim,
fzf, bat, eza, fd, ripgrep, zoxide, starship, fastfetch, calcurse, qalc, tealdeer, tmux, ncmpcpp.

## One theme, everywhere

`tux-theme` renders a single palette into i3/sway, polybar/waybar, rofi/fuzzel, dunst, Alacritty,
GTK 3 (adw-gtk3), GTK 4/libadwaita, **Qt 5/6 (qt5ct/qt6ct, Fusion + the same palette, so Qt and
GTK apps match)**, btop, micro, starship, fzf, zathura, swaylock, the wallpaper, the login screen
and the TTY. Switch with **Super+Ctrl+T** or `tux-theme set nord`.

Own palette: copy any file from `/usr/share/tuxcraft/themes/` to `~/.config/tuxcraft/themes/`,
edit the colours, `tux-theme set <name>`.

## Not breaking the system

| Layer | What happens |
|---|---|
| btrfs layout | `@`, `@home`, `@snapshots`, `@var_log`, `@var_cache`, `@var_tmp`; zstd compression |
| Automatic snapshots | snapper timeline of `/` and `/home`: hourly, daily, weekly, monthly (8/7/4/3 for `/`), plus one per boot; pruned automatically |
| Package snapshots | before/after every pacman (snap-pac) / apt (hook) / `sysup` (Void) transaction |
| Boot a snapshot | GRUB → *tuxcraft snapshots* (grub-btrfs) |
| Roll back | `tux-snap rollback <n>` → reboot. `/home` is never touched |
| Updates | `sysup` (Super+U): battery/space checks, **Arch news gate**, update, flatpaks, cache cleanup, `.pacnew` report, reboot hint |
| Fallback kernel | Arch installs `linux` **and** `linux-lts` |
| Debian | security updates install themselves; everything else waits for `sysup` |
| Off-disk backups | `tux-backup` → incremental `btrfs send` to an external btrfs drive (rsync for other filesystems) |
| `rm` | aliased to `trash-put` in the shell (`rmf` for the real thing) |

Snapshots live on the same disk. They protect against bad updates and mistakes, **not** against a
dead SSD — that is what `tux-backup` is for.

### Recovering from a bad update
1. Reboot, pick **tuxcraft snapshots** in GRUB, choose a snapshot from before the update.
2. Log in (the snapshot is read-only, that's fine), run `tux-snap` to see the list, then
   `tux-snap rollback <n>` and reboot.
3. Later: `tux-snap clean` removes the broken root that was set aside.

## Keys (Super = Windows key)

`Super+K` shows the complete list. The essentials:

| Keys | Action | Keys | Action |
|---|---|---|---|
| Super+Enter | terminal | Super+D | launcher |
| Super+Space | window switcher | Super+Q | close |
| Super+E / Shift+E | Thunar / Thunar in /media | Super+B | browser |
| Super+Escape | **system menu** | Super+U | **update (sysup)** |
| Super+V | clipboard history | Print / Super+Print | screenshot / capture menu |
| Super+Ctrl+T / F / W | theme / font / wallpaper | Super+Ctrl+N / B / A / M | network / bluetooth / audio / btop |
| Super+Shift+L | power menu | Super+Alt+L | lock |
| Super+1..0 | workspaces | Super+Shift+1..0 | move window |
| Super+F | fullscreen | Super+Shift+Space | float / tile |
| Super+T | notes | Super+A | web apps |
| Ctrl+Tab / Ctrl+Shift+Tab | next / previous window in this workspace | Alt+Tab | last workspace |

## Commands

| Command | Does |
|---|---|
| `sysup` | the one safe way to update |
| `tux-snap` | list / create / diff / restore a file / rollback / clean |
| `tux-backup [mountpoint]` | backup to an external drive |
| `tux-theme`, `tux-font`, `tux-wallpaper` | look & feel |
| `tux-pkg install/remove/search/list` | one package command everywhere (`ii`, `rr`, `ss` aliases): host repo first, then Flathub, vendor repos (`data/vendor-repos.tsv`), Arch/Debian/Fedora repos and the AUR in distrobox "boxes"; `sysup` updates the boxes |
| `tux-firewall [status\|on\|off\|allow\|deny]` | nftables firewall: incoming connections blocked except the ports you open to the LAN (`tux-firewall allow 8188/tcp`); SSH is open by default. Never touches libvirt/docker rules |
| `tux-gamevm` | Windows gaming VM with GPU passthrough, single-GPU (desktop) or hybrid (laptop); see below. Appears in the system menu once created |
| `tux-control` | the system menu from a terminal |
| `tux-claude-desktop` | Claude Desktop on any of the three distros (see below) |

## Claude Desktop

Anthropic's Linux app (beta) is only packaged for Debian/Ubuntu, so tuxcraft runs it in a
Debian 13 [distrobox](https://distrobox.it) — the same way on Arch, Debian and Void:

```sh
tux-claude-desktop                    # installs distrobox+podman if needed, builds the box, launches
tux-claude-desktop install --recreate # throw the box away and rebuild it from scratch
tux-claude-desktop doctor             # display, keyring, link handling, sandbox, Cowork/KVM
```

It installs `claude-desktop` from Anthropic's apt repository (signing key checked against its
published fingerprint), exports **Claude** to the app menu, and fixes what breaks in a container:

- **Sign-in:** the box has no browser, so links open on the host through the desktop portal,
  and `claude://` links coming back from the browser are routed to the app in the box.
- **NVIDIA:** the box is created with `--nvidia`, otherwise the app renders without the GPU.
- **Sandbox:** if Chromium's sandbox cannot start in the container, it retries once with
  `--no-sandbox` and remembers that in `~/.config/tuxcraft/claude-desktop.conf`.
- **Updates:** the app does not update itself on Linux; `sysup` upgrades it inside the box.

Sign-in and settings stay in `~/.config/Claude` on the host. Sign-in is saved only if a keyring
(gnome-keyring) runs in your session. **Cowork** needs KVM: be in the `kvm` group and load
`vhost_vsock` (`doctor` prints the commands). Options: `--name` (default `tux-debian`), `--image`.

## Gaming VM (`tux-gamevm`)

Windows with a real GPU, for games that need it. Two modes, picked automatically:

| | single (one GPU, desktop PC) | hybrid (iGPU + dGPU, laptop) |
|---|---|---|
| Starting Windows | closes the Linux desktop, hands over GPU, keyboard, mouse, USB audio | Linux keeps running on the iGPU; only the dGPU leaves |
| Windows' screen | the GPU's monitor | the dGPU's HDMI port, and a **Looking Glass** window on the Linux desktop (keyboard incl. Win-key shortcuts, mouse, sound; clicking in captures, Right Ctrl releases, Right Ctrl+F fullscreen) |
| Shutting Windows down | back to the login screen | the dGPU returns to its Linux driver (CUDA, `nvidia-smi` work again) |

```sh
sudo tux-gamevm setup                    # libvirt, IOMMU, hook; hybrid: X on the iGPU only, Looking Glass, fake battery
sudo tux-gamevm create --image /mnt/data/vm/win.img --size 500 --ram 22 --cores 12 \
     --iso Win10.iso --virtio-win virtio-win.iso --win-user me --win-password ... [--win-key KEY]
tux-gamevm install                       # unattended Windows install in a desktop window (no GPU)
tux-gamevm start                         # with the GPU (hybrid: opens the Looking Glass window)
tux-gamevm guest-setup                   # hybrid, once, while Windows runs: Looking Glass host + virtual monitor
tux-gamevm gpu linux | vm                # hybrid: dGPU for Linux games (prime-run) or for the VM; also in Super+Escape
```

Hybrid **GPU modes** (switch at the next login; X picks its GPUs when it starts): in *vm* mode the desktop never
touches the dGPU, so Windows can take it at any time; in *linux* mode X adds it again and Linux games use it with
`prime-run GAME` (Steam: launch option `prime-run %command%`), while the VM stays off.

`--disk DEV` puts Windows on a whole disk instead of an image. Hybrid notes, learnt on an HP OMEN 16 (RTX 3070 Ti Laptop):
X must not open the dGPU (an X config, and a udev rule that puts its display node on another seat; in vm mode), PipeWire must
leave its HDMI audio alone (it keeps the control device open even when disabled: root-only device nodes), the VM firmware must not run the dGPU's ROM (`rombar=off`, else
warm reboots hang), NVIDIA's laptop driver wants a battery (fake ACPI battery, no error 43), and with nothing on HDMI
Windows needs a virtual monitor for Looking Glass to capture (`guest-setup`: Parsec VDD 0.41 on Windows 10, VDD on
Windows 11, set to the Linux screen's mode, e.g. 1080p @ 165 Hz). LTSC media need `--win-key`
(Microsoft's published KMS client keys install, but do not activate). Windows Update installs the NVIDIA driver.

## Machine-specific fixes

`lib/hwfix.sh` applies fixes only on the exact machine they were tested on (matched by DMI vendor + board):

| Machine | Fix |
|---|---|
| HP OMEN 16-n0xxx (board 8A44, Realtek ALC245) | mute-key LED (the kernel has no quirk for 8A44; it gets its sibling 8A36's, which drives the LED from Realtek coef 0x0b bit 3), and louder built-in speakers: a +6 dB look-ahead limiter on the speaker output only (`~/.config/pipewire/pipewire.conf.d/60-tuxcraft-louder-speakers.conf`) |

## Your own changes

- `~/.config/i3/local.d/*.conf`, `~/.config/sway/local.d/*.conf` — your WM tweaks, never overwritten
- `~/.bashrc.local` — your shell additions
- Re-running the installer moves any config it would overwrite to `~/.local/state/tuxcraft/backup-<date>/`

## Testing in a VM

Before trusting it on a real disk, run a throwaway install in QEMU from your checkout:

```sh
tests/vm-test.sh arch                          # UEFI, i3
tests/vm-test.sh debian --bios --session sway
tests/vm-test.sh void --theme nord --font dos
```

It downloads and checksum-verifies the live ISO, serves the working tree to the VM, and prints
the one line to type in the live console. The install then runs unattended (user `tux`,
password `tux`) and reboots into the new system. There, open a terminal and run the checker:

```sh
curl -fsSL 10.0.2.2:8000/check | bash
```

`tests/vm-check.sh` reports PASS/WARN/FAIL for disk layout, snapshots and rollback tooling,
services, login screen, session programs, TUI apps, theme rendering and fonts, and lists every
package the installer had to skip. It also works on a real machine after an install.
Host needs `qemu`, OVMF/edk2 for UEFI, and KVM for usable speed.

## Honest limitations

- **Tested so far:** every script passes shellcheck; all ten themes are rendered and every generated
  TOML/INI/XML/Qt palette is parsed; the Void package names were checked against void-packages.
  **Not yet tested:** a full install on real hardware or a VM for each distro — `tests/vm-test.sh` exists to do exactly that. Treat the first runs
  as beta and keep the log (`/var/log/tuxcraft.log`).
- No disk encryption (LUKS) yet, and the installer always uses the whole disk (no dual-boot partitioning).
- x86_64 only. Arch + NVIDIA Pascal or older needs the AUR `nvidia-580xx` driver (the script tells you).
- A missing package never stops the install: it is skipped and listed at the end.
