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
      if fetch "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$name.tar.xz" "$t/f.txz"; then
        mkdir -p "$FONT_DIR/$name"
        tar -xJf "$t/f.txz" -C "$FONT_DIR/$name" --wildcards '*.ttf' '*.otf' 2>/dev/null ||
          tar -xJf "$t/f.txz" -C "$FONT_DIR/$name"
      else
        warn "Download of $name failed"
      fi
      rm -rf "$t" ;;
    bundled:*)
      install -Dm644 "$TUX_SRC/assets/fonts/${src#bundled:}" "$FONT_DIR/bundled/${src#bundled:}" ;;
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
    fetch "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$name.tar.xz" "$t/f.txz" &&
      mkdir -p "$FONT_DIR/$name" && tar -xJf "$t/f.txz" -C "$FONT_DIR/$name"
    rm -rf "$t"
  done
  font_install jetbrains
  font_install "$TUX_FONT"
  run fc-cache -f
  ok "Fonts ready ($(font_field "$TUX_FONT" 2))"
}
