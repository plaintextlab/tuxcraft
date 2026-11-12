# tuxcraft

**Easiest:** download `tuxcraft-*.iso` from the [latest release](https://github.com/plaintextlab/tuxcraft/releases/latest),
write it to a USB stick, boot it. The installer starts by itself and asks which Linux you want:
**Arch, Debian or Void**. See [The tuxcraft ISO](#the-tuxcraft-iso).

**Or** boot any of the three distros' own live ISOs, connect to the internet, and run:

```sh
curl -fsSL https://plaintextlab.org/tuxcraft | sh                 # Arch
wget -nv -O- https://plaintextlab.org/tuxcraft | sh              # Debian live
xbps-fetch -o t https://plaintextlab.org/tuxcraft && sh t         # Void
```

Already set up? Update with `tux-update` (or `curl -fsSL https://plaintextlab.org/tuxcraft | sh -s -- --update`).
Which ISO to boot and more: [Quick start](#quick-start).

![tuxcraft on i3: fastfetch, yazi and btop in the kanagawa theme](assets/screenshots/desktop.webp)

One script from a live ISO to a complete, themed, keyboard-driven Linux desktop —
**i3 (X11) or sway (Wayland)** on **Arch, Debian or Void**, with btrfs snapshots that
make a bad update a two-minute fix instead of a reinstall.

It asks a handful of questions, then does everything else: partitioning, base system,
drivers, desktop, TUI apps, fonts, colours, login screen, snapshots and a safe update command.
Configs come from [debi3n](https://github.com/plaintextlab/debi3n), cleaned up and made
distro-neutral.

## Screenshots

| Neovim (LazyVim, VS Code keys) | App launcher (Super+D) |
|---|---|
| ![Neovim with LazyVim and the file explorer](assets/screenshots/neovim.webp) | ![rofi app launcher over the desktop](assets/screenshots/launcher.webp) |
| **Workspace overview (Super+Space)** | **One palette, every app: `tux-theme set <name>`** |
| ![grid of workspace thumbnails](assets/screenshots/overview.webp) | ![the same desktop in Catppuccin Mocha, Gruvbox, Nord and Catppuccin Latte](assets/screenshots/themes.webp) |

The theme grid shows Catppuccin Mocha, Gruvbox, Nord and Catppuccin Latte. The bar, borders,
terminal, file manager, btop, menus and mouse cursor all switch together. Ten themes ship
with tuxcraft (see `themes/`).

## The tuxcraft ISO

One USB stick installs any of the three. It is Arch's official install ISO (same kernel,
firmware and boot loaders) with tuxcraft added and started on the first console.

1. Download `tuxcraft-<version>-x86_64.iso` and check it: `sha256sum -c tuxcraft-*.iso.sha256`.
2. Write it: `sudo dd if=tuxcraft-*.iso of=/dev/sdX bs=4M status=progress oflag=sync` (or Ventoy, Rufus in DD mode).
3. **Turn Secure Boot off** in the firmware settings. The ISO is not signed with Microsoft's key.
4. Boot it. With a network cable it is online at once; otherwise it lists Wi-Fi networks to pick from.
5. Answer the questions: **Arch / Debian / Void**, where to install, encryption, user, desktop.
   Everything else is automatic, then it reboots into your new desktop.

Other consoles (Alt+F2 … F6) are root shells if you want to look around. How the three get
installed from one Arch-based ISO: Arch with `pacstrap`, Debian with `debootstrap` (checked
against Debian's archive key), Void with Void's static `xbps` (checked against Void's signing
keys). After that first step everything runs inside the new system with its own package manager,
exactly as when you start from that distro's own ISO.

**No questions at all:** put an `answers.conf` (see [What it asks](#what-it-asks); the keys are
listed in `./install.sh --help`) on a USB stick or partition labelled `TUXCFG`, optionally with a
`post-hook.sh` that runs as root in the new system at the end. Boot the ISO with it plugged in and
the install runs unattended.

Build it yourself on Arch: `sudo pacman -S archiso && sudo iso/build.sh`.

## Quick start (the distro's own live ISO)

The script keeps working on its own, for when you already booted a live ISO by hand.

Boot the live ISO of the distro you want, connect to the internet, and run **one command**.
It downloads tuxcraft, asks its questions (disk, user, password, desktop, extras…), installs
everything and reboots into the new desktop.

| Distro | Boot this | The one command |
|---|---|---|
| Arch | official `archlinux-*.iso` | `curl -fsSL https://plaintextlab.org/tuxcraft \| sh` |
| Debian | a **live** ISO, e.g. `debian-live-13-*-standard.iso` (the netinst image has no shell) | `wget -nv -O- https://plaintextlab.org/tuxcraft \| sh` |
| Void | `void-live-x86_64-*-base.iso`, glibc (log in as `root`/`voidlinux`) | `xbps-fetch -o t https://plaintextlab.org/tuxcraft && sh t` |

### Connecting to the internet

A network cable just works on Arch and Void. On Debian, run `sudo dhcpcd` once. For Wi-Fi,
first find your Wi-Fi interface: `ip link` lists it, its name starts with `wl` (e.g. `wlan0`,
`wlp2s0`). Replace `wlan0` below with yours, and `MyNetwork` / `MyPassword` with your own
(keep the single quotes).

**Arch** (iwd):

```sh
iwctl station wlan0 scan && iwctl station wlan0 get-networks   # optional: list networks
iwctl --passphrase 'MyPassword' station wlan0 connect 'MyNetwork'
```

**Debian live** (the standard ISO has no NetworkManager, so no nmtui):

```sh
wpa_passphrase 'MyNetwork' 'MyPassword' | sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf >/dev/null
sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf && sudo dhcpcd wlan0
```

**Void** (the base ISO has no NetworkManager either; wpa_supplicant and dhcpcd already run,
and you are root):

```sh
wpa_passphrase 'MyNetwork' 'MyPassword' >> /etc/wpa_supplicant/wpa_supplicant.conf
sv restart wpa_supplicant
```

Then check with `ping -c2 github.com`. If that fails:

- **No `wl…` interface:** the card was not recognised. A cable or USB tethering from your
  phone is the quick way around it (Debian: `sudo dhcpcd`).
- **"RF-kill" / blocked:** Wi-Fi is switched off by a hardware switch or Fn key. Turn it on
  (Arch also has `rfkill unblock wifi`).
- **Still no address:** usually a mistyped name or password. Run `wpa_supplicant` without
  `-B` (Debian/Void) to see why it is refused, or check `iwctl station wlan0 show` (Arch).
- **Desktop live ISO** (GNOME, KDE, Xfce…): it has NetworkManager. Use the panel's Wi-Fi menu
  or `nmtui`.

The Wi-Fi you join here is copied into the new system, so it is online on first boot.

While it installs, every command is shown as it runs (`$ apt-get install …`), with its output
dimmed below it; everything also goes to `/var/log/tuxcraft.log`. If something fails, the
failed command and its error are the last thing on the screen. For a calmer screen that shows
only the steps, run it with `TUX_QUIET=1`, e.g. `wget -nv -O- https://plaintextlab.org/tuxcraft | TUX_QUIET=1 sh`.

Each uses the download tool that ISO already has (curl, wget, xbps-fetch) and needs no git:
the repository comes as a tarball. `| sh` and `| bash` both work. The script becomes
root with sudo when needed and installs curl itself where it is missing. On a system that is
already installed, the same command sets up only the desktop.

`plaintextlab.org/tuxcraft` is a small launcher that fetches the current `install.sh` from this
repository and runs it. The same works straight from GitHub:
`curl -fsSL https://raw.githubusercontent.com/plaintextlab/tuxcraft/main/install.sh | sh`. Pass options after `sh -s --`, e.g.
`curl -fsSL https://plaintextlab.org/tuxcraft | sh -s -- --update`.

On Void, the installer times the mirrors from the official list and uses the fastest
up-to-date one for every repository (no xmirror needed). Re-pick any time with `sudo tux-mirror`
(`--list` shows the timings, `sudo tux-mirror https://…` sets one).

Already have a minimal install (e.g. Debian from the normal installer)? Run the same
command there: tuxcraft detects that it is not on a live ISO and only sets up the desktop
(snapshots are added too if `/` is btrfs).

## What it asks

1. **Which distro** (live ISO only): the tuxcraft ISO offers Arch, Debian and Void; a Debian or
   Void live ISO offers its own distro and the other of those two (Arch needs an Arch host)
2. **Where:** erase a whole disk, use **free space** next to Windows or another system, or replace
   **one partition** (dual boot, UEFI only: the existing EFI partition is shared, never formatted,
   and os-prober adds the other system to the GRUB menu)
3. **Encryption** (default on): LUKS2 over the whole btrfs root including `/boot`. GRUB asks for the
   passphrase once at power-on (US keyboard layout at that prompt); a key file inside the
   encrypted disk spares you a second prompt. Snapshots and rollback work the same.
4. Computer name, user, password, timezone, keyboard. The timezone is **not** looked up online
   unless you say yes (that sends your IP address to ipapi.co).
5. **X11 + i3** or **Wayland + sway** — same keys, same look either way
6. **NVIDIA proprietary driver?** (only asked when an NVIDIA GPU is detected; Intel/AMD just work)
7. **Colour scheme** — Gruvbox, Everforest, Catppuccin Mocha/Latte, Nord, Tokyo Night, Rosé Pine, Kanagawa, Dracula, Motif
8. **Font** (previews below) and size
9. **Browser** and **optional extras** (firewall, Flatpak, wallpapers, Bluetooth, music, printing, dev tools, office, gaming, paru).
   *Music* (on by default) = **rmpc** + mpd with album art and a **cava** visualizer: **Super+M** opens it
   (`8` = full-screen visualizer), **Super+Shift+M** opens cava on its own. Pick the music folder with
   **System menu → Music folder** or `tux-music folder ~/path` — no mpd.conf editing.
   *Gaming* = Steam, gamemode, MangoHud, Heroic (Flatpak), plus the limits Proton needs (`vm.max_map_count`,
   open files); on Void also gamescope, Wine, winetricks, protontricks, vkBasalt and the 32-bit libraries.
   With the NVIDIA driver, the matching Flatpak GL runtime is installed so Flatpak games use the GPU,
   and `/dev/nvidia-uvm` is created at boot so CUDA/NVENC work, also in Flatpak apps (OBS GPU encoding).
   *Printing* and *Office* (LibreOffice) are on by default. Printing sets up CUPS with network
   (mDNS) and USB (ipp-usb) discovery and driverless IPP printing; printers found at install time
   get their vendor driver (hplip, escpr, brlaser, splix). At the first login, printers on the
   network are added automatically; later, **System menu → Printers** or `tux-printer`.
10. Extra packages to **add**, packages to **leave out**

Answers are saved to `/etc/tuxcraft/answers.conf` (without either password); reuse them for an
identical machine with `sudo ./install.sh --config answers.conf --yes`.

## Fonts

![font previews](assets/font-previews/all.png)

Every choice gets Nerd Font icons through a fallback, so the bar and launcher look right even
with the DOS font. Change any time with **Super+Ctrl+F** or `tux-font set dos 13`; the size is the
first entry of that menu (or `tux-font size 13`). The login screen follows both: the font is
rendered as a console font (`tux-psf`) and scaled to the screen, so tuigreet uses the same letters.

## What you get

| Area | X11 session | Wayland session |
|---|---|---|
| Window manager | i3 | sway |
| Bar | polybar | waybar |
| Launcher / menus | rofi | fuzzel |
| Compositor | picom: Hyprland-style animations (springy open, gliding tiles, workspace crossfade) at the monitor's refresh rate | built in |
| Lock / idle | i3lock + xss-lock | swaylock + swayidle |
| Wallpaper | feh | swaybg |
| Clipboard history | CopyQ | cliphist |
| Screenshots / recording | maim, ffmpeg | grim, slurp, wf-recorder |
| Monitors | autorandr / arandr | kanshi |

Shared by both: **kitty** (via `tux-term`), dunst, PipeWire, NetworkManager, polkit agent, gnome-keyring,
udiskie, gammastep (night light), xdg portals, Papirus icons, adw-gtk3.

**Copying to USB sticks shows the real progress:** USB disks and SD cards may hold at most 16 MiB
of unwritten data in RAM, so a copy no longer jumps to 100% and then hangs while the data is
still being written (or the unmount does). Internal disks keep the normal large write cache.

**Login screen:** greetd + **tuigreet** — a TUI login that fits a keyboard-driven setup, works with
X11 and Wayland, systemd and runit, and is coloured by the system theme (the console palette is
themed too) and drawn in the desktop font at a matching size. LightDM is used only if tuigreet is
not packaged.

**Terminal and images:** kitty is the default because it shows real images (kitty graphics
protocol, X11 and Wayland): album art in rmpc, image previews in yazi, and `img photo.jpg` for any
picture (chafa; block art over ssh/tmux). Everything opens the terminal through `tux-term`; for
Alacritty instead, put `TERMINAL=alacritty` in `~/.config/tuxcraft/state` (no images there).
kitty runs as one process for all windows, so a new terminal opens instantly, and its cursor
leaves a short trail when it jumps.

**Shell:** bash with **ble.sh**: grey command hints from history as you type (→ or End accepts,
Alt+F takes one word), syntax colours and a completion menu (off: `touch ~/.config/tuxcraft/no-blesh`).
History keeps 200,000 commands with no duplicates and none of the noise (`clear`, `ls`, `cd`, ...),
is saved after every command, and is searched with **Ctrl+R** (fzf) or by typing the start of a
command and pressing **Up/Down**.

**Neovim = LazyVim, set up like VS Code** (`nvim`): file tree, tabs, fuzzy finder, LSP, completion,
format on save and git signs, ready on first start (the installer pre-installs the plugins).
Python, TypeScript/JavaScript, JSON, YAML, TOML, Markdown, Docker and git files are set up;
their language servers install on first use (`:Mason`), more languages via `:LazyExtras`.
Colours follow the tuxcraft scheme (its real Neovim theme, or your palette via mini.base16).

| VS Code key | Does |
|---|---|
| Ctrl+P / F1 | find file / command palette |
| Ctrl+Shift+F | search in all files |
| Ctrl+B | file explorer |
| Ctrl+/ | toggle comment |
| Ctrl+S | save |
| F2 / F12 / Ctrl+. | rename / go to definition / quick fix |
| Shift+Alt+F | format |
| Alt+↑ / Alt+↓ | move line |
| Ctrl+Tab | next tab |
| Ctrl+\` | terminal |

Everything else: press **Space** and wait, a menu of every command appears.

**Mouse cursor:** coloured like the scheme (Catppuccin cursors in the shade closest to the accent,
picked and downloaded by `tux-theme`); `CURSOR=Adwaita` in the state file keeps the plain one.

**Fast app start (`tux-warm`):** the browser, the terminal and the file manager open faster. Every
10 minutes their programs, libraries and app folders, plus what every desktop app loads (the
graphics driver, font and icon caches), are read into the page cache at idle disk priority. The
terminal's and Thunar's light server modes also stay running (`alacritty --daemon`, a hidden kitty
instance, `thunar --daemon`), so a new window appears at once. Time to the first window, cold vs. warm
(SATA SSD, software-rendered X, so GPU apps are slower than usual):

| App | cold | warmed | from its server mode |
|---|---|---|---|
| Alacritty | ~540 ms | ~190 ms | ~85 ms |
| Thunar | ~810 ms | ~520 ms | ~90 ms |
| Firefox | ~1.7 s | ~1.25 s | – |
| kitty | – | ~770 ms | ~60 ms |

It never makes memory tight. Warmed files are ordinary page cache, which the kernel hands to any
program that needs RAM. Nothing is locked (no `mlock`, no RAM disk), and the total is capped at 10%
of RAM. Server modes run only with 8 GB of RAM or more. Warming pauses, and idle server modes stop,
while MemAvailable is under 25% of RAM (or 2 GB), memory pressure is above 0.5%, or a big program or
game runs (Steam, gamescope, the gaming VM, DaVinci Resolve, Blender, Wine/Proton, OBS, Kdenlive).
They come back 2 minutes after that ends. A server mode holding one of your windows is never closed
under you. Which apps, the limits and the big-program list: `~/.config/tuxcraft/warm.conf`
(`tux-warm --edit`; written on first start, never overwritten). `tux-warm status` shows what is
warm and how much of it is in RAM.

**Off switch:** system menu (Super+Escape) → *Fast app start: switch off*, or `tux-warm off`.
It stays off after the next login; `tux-warm on` turns it back on. Idle server modes close at once;
one that still holds a terminal or Thunar window closes with that window.

**Files:** Thunar (right-click → Open Terminal Here), yazi in the terminal.
**TUI apps:** yazi (files), btop, lazygit, wifitui (Wi-Fi; nmtui for wired/VPN), bluetui, wiremix/pulsemixer, ncdu, micro + neovim,
fzf, bat, eza, fd, ripgrep, zoxide, starship, fastfetch, calcurse, qalc, tealdeer, tmux, rmpc, cava.

## One theme, everywhere

`tux-theme` renders a single palette into i3/sway, polybar/waybar, rofi/fuzzel, dunst, kitty, Alacritty, rmpc, cava,
GTK 3 (adw-gtk3), GTK 4/libadwaita, **Qt 5/6 (qt5ct/qt6ct, Fusion + the same palette, so Qt and
GTK apps match)**, btop, micro, starship, fzf, zathura, swaylock, the wallpaper, the login screen
and the TTY. Switch with **Super+Ctrl+T** or `tux-theme set nord`.

**Firefox** follows too (`tux-firefox`, run by every theme or font change): tabs, toolbar,
address bar, menus and the new-tab page take the palette, with square corners on menus,
panels, buttons and tabs; it switches to dark or light with the theme; and every website shows
its text in your UI font and code in your terminal font (icon fonts still load). Firefox reads
this when it starts, so restart it after a change; the theme notification reminds you. It
covers every profile of Firefox, Flatpak Firefox and LibreWolf, and keeps your own
`userChrome.css` and `user.js` (tuxcraft adds one `@import` line and a marked block).
Settings in `~/.config/tuxcraft/state`: `FIREFOX_CORNERS=round` keeps Firefox's rounded
corners, `FIREFOX_FONTS=site` lets websites use their own fonts again, `FIREFOX_THEME=no`
leaves Firefox alone.

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
| Shutdown guard | logout / reboot / shutdown from the power menu first lists what would be lost (DaVinci Resolve, OBS recording, unsaved windows, file copies, package updates, VMs, downloads …) and asks; Cancel is the default. Edit the list: system menu → *Shutdown guard list*, or `~/.config/tuxcraft/power-guard.conf` |
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
| Super+Space | **workspace overview** (thumbnails, pick one) | Super+Q | close |
| Super+E / Shift+E | Thunar / Thunar in /media | Super+B | browser |
| Super+Escape | **system menu** | Super+U | **update (sysup)** |
| Super+V | clipboard history | Print / Super+Print | screenshot / capture menu |
| Super+Ctrl+T / F / W | theme / font / wallpaper | Super+Ctrl+N / B / A / M | network / bluetooth / audio / btop |
| Super+Shift+L | power menu | Super+Alt+L | lock |
| Super+1..0 | workspaces | Super+Shift+1..0 | move window |
| Super+O | window switcher | Super+Tab / Shift+Tab | next / previous workspace |
| Super+F | fullscreen | Super+Shift+Space | float / tile |
| Super+T | notes | Super+A | web apps |
| Super+Alt+Tab / +Shift | next / previous window in this workspace | Alt+Tab (hold Alt) | **workspace switcher**, most recent first (tap: last workspace) |
| Super+F1 … F11 | brightness (+ monitor contrast) 0% … 100% | Super+Alt+Up / Down | brightness; below 0% dims to −80% |

## Commands

| Command | Does |
|---|---|
| `sysup` | the one safe way to update |
| `tux-update` | update tuxcraft itself (tools, configs, fixes) with your saved choices; same as the `--update` one-liner. Also in the System menu → Update tuxcraft |
| `tux-snap` | list / create / diff / restore a file / rollback / clean |
| `tux-backup [mountpoint]` | backup to an external drive |
| `tux-drives [list\|on\|off NAME]` | choose which drives mount by themselves (System menu → Drives): internal ones go in `/etc/fstab` with `nofail` and mount at boot under `/media/<label>`; external ones are mounted by udiskie when plugged in, unless you switch them off |
| `tux-theme`, `tux-font`, `tux-wallpaper` | look & feel |
| `tux-pkg install/remove/search/list` | one package command everywhere (`ii`, `rr`, `ss` aliases): host repo first, then Flathub, vendor repos (`data/vendor-repos.tsv`), Arch/Debian/Fedora repos and the AUR in distrobox "boxes"; `sysup` updates the boxes |
| `tux-firewall [status\|on\|off\|allow\|deny]` | nftables firewall: incoming connections blocked except the ports you open to the LAN (`tux-firewall allow 8188/tcp`); SSH is open by default. Never touches libvirt/docker rules |
| `tux-gamevm` | Windows gaming VM with GPU passthrough, single-GPU (desktop) or hybrid (laptop); see below. Appears in the system menu once created |
| `tux-guard --list` / `--edit` | what would block a shutdown right now / edit the watch list |
| `tux-warm status` / `off` / `on` / `--edit` | fast app start: what is kept warm, switch it off/on, choose the apps |
| `tux-dwt status` / `restart` | touchpad off while typing (i3), back 600 ms after the last key; `DWT_MS=` in `~/.config/tuxcraft/state` changes the delay, `0` turns it off |
| `tux-control` | the system menu from a terminal |
| `tux-claude-desktop` | Claude Desktop on any of the three distros (see below) |

## Claude Desktop

Anthropic's Linux app (beta) is only packaged for Debian/Ubuntu, so tuxcraft runs it in a
Debian 13 [distrobox](https://distrobox.it) — the same way on Arch, Debian and Void:

```sh
tux-claude-desktop                    # installs distrobox+podman if needed, builds the box, launches
tux-claude-desktop install --recreate # throw the box away and rebuild it from scratch
tux-claude-desktop doctor             # display, keyring, link handling, sandbox, Cowork/KVM
tux-claude-desktop menu               # (re)create the Claude entry in the app launcher
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
| HP OMEN 16-n0xxx (board 8A44, Realtek ALC245) | mute-key LED (the kernel has no quirk for 8A44; it borrows HP board 8A25's (kernel 6.6+), which drives the LED from Realtek coef 0x0b bit 3), and louder built-in speakers: a +6 dB look-ahead limiter on the speaker output only (`~/.config/pipewire/pipewire.conf.d/60-tuxcraft-louder-speakers.conf`). The speaker amp switches off on silence and drops the first word after every pause, so the same filter mixes in an inaudible 15 kHz tone that `tux-speaker-tone` keeps at the same level at the speakers whatever the volume, and the speakers sleep 30 s after the last sound instead of 5 s (`~/.config/wireplumber/wireplumber.conf.d/60-tuxcraft-speaker-sleep.conf`) |

## Your own changes

- `~/.config/i3/local.d/*.conf`, `~/.config/sway/local.d/*.conf` — your WM tweaks, never overwritten
- `~/.bashrc.local` — your shell additions
- `~/.config/tuxcraft/power-guard.conf` — apps and tasks the shutdown guard watches, never overwritten
- `~/.config/tuxcraft/warm.conf` — fast app start: which apps, memory limits, the big-program list
- Re-running the installer moves any config it would overwrite to `~/.local/state/tuxcraft/backup-<date>/`

## Trust: what runs as root

- **Releases are pinned.** `https://plaintextlab.org/tuxcraft` serves the `install.sh` of the
  latest GitHub release, which downloads that release's tarball and refuses it unless its SHA-256
  matches. The `install.sh` on the `main` branch follows `main` unverified: the development channel.
- **Every upstream download is pinned.** Tools no distro packages (yazi, Neovim, starship, lazygit,
  Nerd Fonts, …) have a fixed version and SHA-256 in `data/downloads.tsv`; a file that does not
  match is refused. `scripts/update-pins.sh` bumps them; CI runs it weekly and opens a pull request.
- **Your password** reaches the new system through a root-only file on its `/run` (RAM), never
  its disk, and is not saved in `answers.conf`.

## Testing in a VM

**CI** (`.github/workflows/ci.yml`) builds the ISO and installs from it in QEMU/KVM on every push to
`main`: Arch, Debian and Void, each with i3 and with sway, encrypted and not, one BIOS install
and one dual-boot (free space) install. The installed system boots, runs `tests/vm-check.sh` and
the job fails on any FAIL. Locally the same: `tests/ci-vm.sh out/tuxcraft-*.iso debian --luks`.

By hand, with the distros' own ISOs:

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

- **Tested so far:** every script passes shellcheck (no warnings); all ten themes are rendered and every generated
  TOML/INI/XML/Qt palette is parsed; the Void package names were checked against void-packages.
  Full installs are covered by the CI matrix above; until it has passed on real hardware for
  each distro, treat the first runs as beta and keep the log (`/var/log/tuxcraft.log`).
- The tuxcraft ISO needs **Secure Boot off**.
- Dual boot needs UEFI and a GPT disk. BIOS installs always use a whole disk.
- Encrypted installs: GRUB unlocks the disk slowly (PBKDF2, about 5–15 s) and always with a US
  keyboard layout. No TPM unlock, no hibernation.
- x86_64 only. Arch + NVIDIA Pascal or older needs the AUR `nvidia-580xx` driver (the script tells you).
- A missing package never stops the install: it is skipped and listed at the end.
