# shellcheck shell=bash
# Fonts: Nerd Fonts from upstream releases (same version on every distro).

FONT_DIR=/usr/local/share/fonts/tuxcraft
FONT_TABLE=${FONT_TABLE:-$TUX_SRC/data/fonts.tsv}

font_field() {  # font_field key column(2=family,3=source,4=desc)
  awk -F'\t' -v k="$1" -v c="$2" '$1==k {print $c}' "$FONT_TABLE"
}

font_choices() {  # "key|family|desc" lines for choose()
  awk -F'\t' '!/^#/ && NF>=4 {print $1 "|" $2 "|" $4}' "$FONT_TABLE"
}

font_install() {  # font_install key
  local src; src=$(font_field "$1" 3)
  case $src in
    nerd:*)
      local name=${src#nerd:}
      [[ -d $FONT_DIR/$name ]] && return 0
      local t; t=$(mktemp -d)
      info "Downloading $name Nerd Font"
      if run pin_get "nerd:$name" "$t/f.txz"; then
        mkdir -p "$FONT_DIR/$name"
        tar -xJf "$t/f.txz" -C "$FONT_DIR/$name" --wildcards '*.ttf' '*.otf' 2>/dev/null ||
          tar -xJf "$t/f.txz" -C "$FONT_DIR/$name"
      else
        warn "Download of $name failed"
      fi
      rm -rf "$t" ;;
    bundled:*)
      # Copy only when it changed: rewriting it on every update touches the directory, and
      # fc-cache then finds the directory newer than the cache it has just written.
      local f=${src#bundled:}
      cmp -s "$TUX_SRC/assets/fonts/$f" "$FONT_DIR/bundled/$f" ||
        install -Dm644 "$TUX_SRC/assets/fonts/$f" "$FONT_DIR/bundled/$f" ;;
    system:*) : ;;
  esac
}

fonts_stage() {
  step "Fonts"
  # Symbols Nerd Font gives every font the bar/launcher icons; JetBrains is the mono fallback.
  mkdir -p "$FONT_DIR"
  local name t
  for name in NerdFontsSymbolsOnly; do
    [[ -d $FONT_DIR/$name ]] && continue
    t=$(mktemp -d)
    if run pin_get "nerd:$name" "$t/f.txz"; then
      mkdir -p "$FONT_DIR/$name" && tar -xJf "$t/f.txz" -C "$FONT_DIR/$name"
    else
      warn "Download of $name failed: bar and launcher icons will be missing"
    fi
    rm -rf "$t"
  done
  font_install jetbrains
  font_install "$TUX_FONT"
  fonts_cache || warn "Font cache not rebuilt: fonts still work, apps just start a little slower"
  ok "Fonts ready ($(font_field "$TUX_FONT" 2))"
}

# fc-cache prints "<dir>: failed to write cache" and exits non-zero when a directory's mtime does
# not match the cache it has just written: a directory dated in the future (made while the clock
# was wrong: Windows dual boot, before NTP), or a lock left by an interrupted run. Fix both, try
# again, and never stop the install over it: fontconfig scans directories that have no cache.
fonts_cache() {
  local d
  for d in /usr/local/share/fonts /usr/share/fonts; do
    [[ -d $d ]] || continue
    find "$d" -type d -newermt now -exec touch {} + 2>/dev/null || :
  done
  find /var/cache/fontconfig -maxdepth 1 -name '*.LCK' -mmin +1 -delete 2>/dev/null || :
  run fc-cache -f && return 0
  sleep 1
  run fc-cache -f
}
