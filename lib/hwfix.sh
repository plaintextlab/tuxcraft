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
#   * mute-key LED: the kernel has no quirk for 8A44, so borrow the one of HP board 8A25
#     (Victus 16-d1xxx, ALC245_FIXUP_HP_MUTE_LED_COEFBIT, in kernels 6.6 and later)
#     (Realtek coef 0x0b bit 3 follows the mute state; it changes nothing else)
#   * built-in speakers are quieter than on Windows, which adds HP/DTS processing: a look-ahead
#     limiter in front of the speaker output only (+6 dB, peaks held at -1 dBFS)
#   * the speaker amp switches itself off during digital silence and takes a moment to wake, so the
#     first word after a pause (or after playback starts) never comes out of the speakers. Keep it
#     awake: mix a 15 kHz tone at -80 dBFS (inaudible) into the speaker filter. It only flows while
#     something plays through the speakers: the filter's output is passive, so the speakers still
#     suspend after the last stream stops (30 s instead of WirePlumber's 5 s, so a short stop
#     between clips doesn't make the amp sleep and eat the next first word), and with headphones
#     in (separate card profile) or Bluetooth/HDMI as the output the tone stops.
#     Measured on this laptop: random noise at -96 dBFS still lets the amp sleep, -90 keeps it on;
#     a -80 dBFS sine at 50 Hz, 1 kHz or 15 kHz keeps it on too. PipeWire's own dither.noise
#     (even 11 bits, with or without dither.method) did NOT keep it on.
#     The speaker volume is applied after the filter (in the codec), so it turns the tone down too:
#     at 60 % the amp slept again. tux-speaker-tone (started by PipeWire) raises the tone by what
#     the volume takes away, so the speakers always get about -74 dBFS.
hwfix_hp_omen_8a44() {
  info "HP OMEN 16 (8A44): mute LED + louder speakers + speaker amp kept awake"
  write_file /usr/lib/firmware/tuxcraft/hda-hp-8a44.fw <<'EOF'
[codec]
0x10ec0245 0x103c8a44 0

[model]
103c:8a25
EOF
  local fw=tuxcraft/hda-hp-8a44.fw
  write_file /etc/modprobe.d/tuxcraft-hp-omen-audio.conf <<EOF
# tuxcraft: HP OMEN 16-n0xxx (board 8A44) mute-key LED. The kernel has no quirk for this board;
# borrow the one of HP board 8A25 (ALC245_FIXUP_HP_MUTE_LED_COEFBIT: mute LED on Realtek coef 0x0b
# bit 3, nothing else; kernel 6.6+). 8A36, used before, has no quirk in any kernel.
# The patch file only applies to the codec it names, so listing it for every card is safe.
options snd-hda-intel patch=$fw,$fw,$fw,$fw
EOF

  pkg_install swh-plugins
  local pci
  pci=$(hda_card_pci 0x10ec0245 0x103c8a44) || { warn "ALC245 not found; skipping the speaker limiter"; return 0; }
  write_file "$TUX_HOME/.config/wireplumber/wireplumber.conf.d/60-tuxcraft-speaker-sleep.conf" <<EOF
# tuxcraft: HP OMEN 16-n0xxx built-in speakers go to sleep 30 s after the last sound stops
# (WirePlumber's default is 5 s). Waking them clips the first word, so a longer wait means a short
# stop between clips doesn't eat it. Only the speaker output; headphones, Bluetooth and HDMI keep
# the default. Remove this file to go back to 5 s.
monitor.alsa.rules = [
  { matches = [ { node.name = "alsa_output.$pci.HiFi__Speaker__sink" } ]
    actions = { update-props = { session.suspend-timeout-seconds = 30 } }
  }
]
EOF
  chown -R "$TUX_USER:" "$TUX_HOME/.config/wireplumber"
  write_file "$TUX_HOME/.config/pipewire/pipewire.conf.d/60-tuxcraft-louder-speakers.conf" <<EOF
# tuxcraft: louder built-in speakers (written for HP OMEN 16-n0xxx).
# A look-ahead limiter in front of the speaker output only (WirePlumber smart filter):
# +6 dB, peaks held at -1 dBFS, so it gets louder without clipping. After it, a quiet 15 kHz tone
# is mixed in: the speaker amp switches off on silence and eats the first word after every
# pause, and this keeps it awake. tux-speaker-tone raises the tone as the volume goes down
# (the volume is applied after this filter), so the speakers always get about -74 dBFS
# (inaudible). Headphones, Bluetooth and HDMI are separate outputs and are not touched.
# Remove this file to turn it off.
context.exec = [ { path = "/usr/local/bin/tux-speaker-tone" args = "" } ]
context.modules = [
  { name = libpipewire-module-filter-chain
    args = {
      node.description = "Speakers (louder)"
      media.name       = "Speakers (louder)"
      filter.graph = {
        nodes = [
          { type = ladspa name = lim plugin = fast_lookahead_limiter_1913 label = fastLookaheadLimiter
            control = { "Input gain (dB)" = 6.0 "Limit (dB)" = -1.0 "Release time (s)" = 0.1 } }
          { type = builtin name = tone label = sine control = { "Freq" = 15000.0 "Ampl" = 0.0002 } }
          { type = builtin name = mixL label = mixer control = { "Gain 1" = 1.0 "Gain 2" = 1.0 } }
          { type = builtin name = mixR label = mixer control = { "Gain 1" = 1.0 "Gain 2" = 1.0 } }
        ]
        links = [
          { output = "lim:Output 1" input = "mixL:In 1" }
          { output = "tone:Out"     input = "mixL:In 2" }
          { output = "lim:Output 2" input = "mixR:In 1" }
          { output = "tone:Out"     input = "mixR:In 2" }
        ]
        inputs  = [ "lim:Input 1" "lim:Input 2" ]
        outputs = [ "mixL:Out" "mixR:Out" ]
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
