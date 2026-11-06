# shellcheck shell=bash
# Pinned upstream downloads: every file tuxcraft fetches from outside a distro repository has a
# fixed version and a SHA-256 in data/downloads.tsv, and is refused when the hash does not match.
# A compromised or re-uploaded release then stops at the checksum instead of running as root.
#
# Standalone on purpose (needs only bash, curl, sha256sum): the installer sources it from lib/,
# and the tux-* tools source it from /usr/share/tuxcraft/lib/ on the installed system.
#
#   pin_version KEY          -> v1.2.3
#   pin_url KEY              -> https://... (version filled in)
#   pin_get KEY DEST         download KEY to DEST, verified; fails (and leaves no DEST) otherwise
#
# Bump versions with scripts/update-pins.sh (CI does this weekly and opens a pull request).

PIN_TABLE=${PIN_TABLE:-${TUX_SRC:-${TUX_SHARE:-/usr/share/tuxcraft}}/data/downloads.tsv}

# Columns: key  track  version  url  sha256
_pin_row() {
  awk -F'\t' -v k="$1" '!/^#/ && $1 == k { print; found = 1; exit } END { exit !found }' "$PIN_TABLE"
}

pin_field() {  # pin_field KEY COLUMN(2=track 3=version 4=url 5=sha256)
  local row
  row=$(_pin_row "$1") || { echo "pins: unknown download '$1'" >&2; return 1; }
  awk -F'\t' -v c="$2" '{ print $c }' <<<"$row"
}

pin_version() { pin_field "$1" 3; }

# {v} = version as tagged (v1.2.3), {V} = without the leading "v" (1.2.3).
pin_url() {
  local v u
  v=$(pin_field "$1" 3) && u=$(pin_field "$1" 4) || return 1
  u=${u//\{v\}/$v}
  printf '%s\n' "${u//\{V\}/${v#v}}"
}

pin_get() {  # pin_get KEY DEST
  local key=$1 dest=$2 url sum got
  url=$(pin_url "$key") && sum=$(pin_field "$key" 5) || return 1
  if [[ ! $sum =~ ^[0-9a-f]{64}$ ]]; then
    echo "pins: no checksum recorded for '$key' (run scripts/update-pins.sh); refusing to download" >&2
    return 1
  fi
  mkdir -p "$(dirname "$dest")"
  curl -fL --retry 3 --connect-timeout 15 --no-progress-meter -o "$dest.part" "$url" || { rm -f "$dest.part"; return 1; }
  got=$(sha256sum "$dest.part" | awk '{ print $1 }')
  if [[ $got != "$sum" ]]; then
    rm -f "$dest.part"
    echo "pins: CHECKSUM MISMATCH for $key ($url)" >&2
    echo "pins:   expected $sum" >&2
    echo "pins:   got      $got" >&2
    return 1
  fi
  mv -f "$dest.part" "$dest"
}
