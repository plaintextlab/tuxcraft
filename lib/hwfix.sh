# shellcheck shell=bash
# Fixes for specific machines, picked by DMI vendor + board. Each one is tested on that machine;
# nothing here runs anywhere else.

hw_board() { echo "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null):$(cat /sys/class/dmi/id/board_name 2>/dev/null)"; }

# PCI name of the sound card whose codec matches "vendorid subsystemid", e.g. pci-0000_07_00.6
hda_card_pci() {
  local c card
  for c in /proc/asound/card*/codec#*; do
    grep -q "^Vendor Id: $1$" "$c" && grep -q "^Subsystem Id: $2$" "$c" || continue
    card=${c#/proc/asound/}; card=${card%%/*}
    basename "$(readlink -f "/sys/class/sound/$card/device")" | sed 's/^/pci-/; s/:/_/g'
    return 0
  done
  return 1
}

# HP OMEN 16-n0xxx (AMD, board 8A44, Realtek ALC245):
#   * mute-key LED: the kernel has no quirk for 8A44, so borrow its sibling 8A36's
#     (Realtek coef 0x0b bit 3 follows the mute state; it changes nothing else)
#   * built-in speakers are quieter than on Windows, which adds HP/DTS processing: a look-ahead
#     limiter in front of the speaker output only (+6 dB, peaks held at -1 dBFS)
hwfix_hp_omen_8a44() {
  info "HP OMEN 16 (8A44): mute LED + louder speakers"
  write_file /usr/lib/firmware/tuxcraft/hda-hp-8a44.fw <<'EOF'
[codec]
0x10ec0245 0x103c8a44 0

[model]
103c:8a36
EOF
  local fw=tuxcraft/hda-hp-8a44.fw
  write_file /etc/modprobe.d/tuxcraft-hp-omen-audio.conf <<EOF
# tuxcraft: HP OMEN 16-n0xxx (board 8A44) mute-key LED. The kernel has no quirk for this board;
# borrow the one of its sibling 8A36 (fixup: mute LED on Realtek coef 0x0b bit 3, nothing else).
# The patch file only applies to the codec it names, so listing it for every card is safe.
options snd-hda-intel patch=$fw,$fw,$fw,$fw
EOF

  pkg_install swh-plugins
  local pci
  pci=$(hda_card_pci 0x10ec0245 0x103c8a44) || { warn "ALC245 not found; skipping the speaker limiter"; return 0; }
  write_file "$TUX_HOME/.config/pipewire/pipewire.conf.d/60-tuxcraft-louder-speakers.conf" <<EOF
# tuxcraft: louder built-in speakers (written for HP OMEN 16-n0xxx).
# A look-ahead limiter in front of the speaker output only (WirePlumber smart filter):
# +6 dB, peaks held at -1 dBFS, so it gets louder without clipping. Headphones, Bluetooth and
# HDMI are separate outputs and are not touched. Remove this file to turn it off.
context.modules = [
  { name = libpipewire-module-filter-chain
    args = {
      node.description = "Speakers (louder)"
      media.name       = "Speakers (louder)"
      filter.graph = {
        nodes = [
          { type = ladspa name = lim plugin = fast_lookahead_limiter_1913 label = fastLookaheadLimiter
            control = { "Input gain (dB)" = 6.0 "Limit (dB)" = -1.0 "Release time (s)" = 0.1 } }
        ]
        inputs  = [ "lim:Input 1" "lim:Input 2" ]
        outputs = [ "lim:Output 1" "lim:Output 2" ]
      }
      audio.channels = 2
      audio.position = [ FL FR ]
      capture.props = {
        node.name   = "tuxcraft.louder-speakers"
        media.class = Audio/Sink
        filter.smart = true
        filter.smart.name = "tuxcraft-louder-speakers"
        filter.smart.target = { node.name = "alsa_output.$pci.HiFi__Speaker__sink" }
      }
      playback.props = {
        node.name    = "tuxcraft.louder-speakers.out"
        node.passive = true
      }
    }
  }
]
EOF
  chown -R "$TUX_USER:" "$TUX_HOME/.config/pipewire"
}

hwfix_stage() {
  case $(hw_board) in
    HP:8A44) hwfix_hp_omen_8a44 ;;
    *) return 0 ;;
  esac
}
