#!/usr/bin/env bash
# update-pins.sh — bump data/downloads.tsv to the newest upstream versions and record SHA-256s.
#
#   scripts/update-pins.sh            update every row (downloads only what changed)
#   scripts/update-pins.sh --force    re-download and re-hash everything
#   scripts/update-pins.sh --check    no network: fail if any row lacks a version or a hash
#
# Run on a trusted machine and review the diff: a new hash means "this is the file I vetted".
# CI runs it weekly and opens a pull request (.github/workflows/pins.yml).
# Needs: bash, curl, sha256sum, git, xz, python3 (only for the GitHub asset list of cursors).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
TABLE=${TABLE:-$HERE/../data/downloads.tsv}
FORCE=0 CHECK=0
case ${1:-} in
  --force) FORCE=1 ;; --check) CHECK=1 ;; '') ;;
  -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown option $1" >&2; exit 1 ;;
esac

# Rows have empty columns (no version or hash yet). Tab is whitespace to `read`, so runs of
# tabs would collapse and shift the columns: split on \x1f instead.
us_split() { tr '\t' '\037'; }

if ((CHECK)); then
  bad=0
  while IFS=$'\x1f' read -r key track ver url sum; do
    [[ -z $key || $key == \#* || $key == cursors ]] && continue
    [[ -n $ver ]] || { echo "no version: $key" >&2; bad=1; }
    [[ $sum =~ ^[0-9a-f]{64}$ ]] || { echo "no sha256: $key" >&2; bad=1; }
    [[ $track == latest:* || $track == commit:* || $track == fixed || $track == debian:* || $track == void-static ]] ||
      { echo "unknown track '$track': $key" >&2; bad=1; }
  done < <(us_split <"$TABLE")
  grep -q $'^cursor:' "$TABLE" || { echo "no cursor:* rows (run without --check)" >&2; bad=1; }
  ((bad)) && exit 1
  echo "pins OK: $(grep -cv '^#' "$TABLE") rows"
  exit 0
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
declare -A LATEST=()
CURL=(curl -fsSL --retry 3 --connect-timeout 15)
[[ -n ${GITHUB_TOKEN:-} ]] && GH_AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN") || GH_AUTH=()

gh_latest() {  # owner/repo -> tag (memoised: all nerd fonts share one lookup)
  [[ -n ${LATEST[$1]:-} ]] || LATEST[$1]=$("${CURL[@]}" -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's#.*/tag/##')
  [[ -n ${LATEST[$1]} && ${LATEST[$1]} != http* ]] || { echo "no latest release for $1" >&2; return 1; }
  echo "${LATEST[$1]}"
}

resolve() {  # track current-version -> version
  local track=$1 cur=$2
  case $track in
    fixed) echo "$cur" ;;
    latest:*) gh_latest "${track#latest:}" ;;
    commit:*)
      local repo=${track#commit:}; local ref=${repo#*@}; repo=${repo%@*}
      git ls-remote "https://github.com/$repo" "refs/heads/$ref" | awk '{ print $1; exit }' ;;
    debian:*)  # debian:SUITE/PACKAGE -> pool path
      local suite=${track#debian:}; local pkg=${suite#*/}; suite=${suite%/*}
      [[ -f $TMP/Packages.$suite ]] || "${CURL[@]}" "https://deb.debian.org/debian/dists/$suite/main/binary-amd64/Packages.xz" | xz -d >"$TMP/Packages.$suite"
      awk -v p="$pkg" '$1 == "Package:" { hit = ($2 == p) } hit && $1 == "Filename:" { print $2; exit }' "$TMP/Packages.$suite" ;;
    void-static)
      "${CURL[@]}" https://repo-default.voidlinux.org/static/ |
        grep -oE 'xbps-static-static-[0-9][0-9._]*_[0-9]+\.x86_64-musl\.tar\.xz' |
        sed -E 's/^xbps-static-static-(.*)\.x86_64-musl\.tar\.xz$/\1/' | sort -uV | tail -n1 ;;
    *) echo "unknown track $track" >&2; return 1 ;;
  esac
}

fill() { local u=${1//\{v\}/$2}; printf '%s\n' "${u//\{V\}/${2#v}}"; }

hash_of() {  # template version -> "template sha" (first alternative that downloads)
  local alt u
  IFS='|' read -ra alts <<<"$1"
  for alt in "${alts[@]}"; do
    alt=$(sed 's/^ *//; s/ *$//' <<<"$alt")
    u=$(fill "$alt" "$2")
    if "${CURL[@]}" -o "$TMP/f" "$u" 2>/dev/null; then
      printf '%s\t%s\n' "$alt" "$(sha256sum "$TMP/f" | awk '{ print $1 }')"
      return 0
    fi
  done
  echo "download failed: $(fill "$1" "$2")" >&2
  return 1
}

cursor_rows() {  # version -> one row per .zip of the catppuccin/cursors release
  local v=$1 name sum
  "${CURL[@]}" "${GH_AUTH[@]}" "https://api.github.com/repos/catppuccin/cursors/releases/tags/$v" |
    python3 -c 'import json, sys; [print(a["name"][:-4]) for a in json.load(sys.stdin)["assets"] if a["name"].endswith(".zip")]' |
    sort | while read -r name; do
      "${CURL[@]}" -o "$TMP/c" "https://github.com/catppuccin/cursors/releases/download/$v/$name.zip"
      sum=$(sha256sum "$TMP/c" | awk '{ print $1 }')
      printf 'cursor:%s\tfixed\t%s\thttps://github.com/catppuccin/cursors/releases/download/{v}/%s.zip\t%s\n' "$name" "$v" "$name" "$sum"
    done
}

out=$TMP/new.tsv fail=0 changed=0
declare -A OLD_CURSOR=()
while IFS=$'\x1f' read -r key _ ver _ sum; do
  [[ $key == cursor:* ]] && OLD_CURSOR[$key]="$ver $sum"
done < <(us_split <"$TABLE")

while IFS= read -r line; do
  if [[ -z $line || $line == \#* ]]; then echo "$line" >>"$out"; continue; fi
  IFS=$'\x1f' read -r key track ver url sum <<<"${line//$'\t'/$'\x1f'}"
  [[ $key == cursor:* ]] && continue   # regenerated below the "cursors" row
  if [[ $key == cursors ]]; then
    echo "$line" >>"$out"
    if ((FORCE)) || ((${#OLD_CURSOR[@]} == 0)) || [[ ${OLD_CURSOR[*]} != *"$ver "* ]]; then
      echo ":: cursors $ver"
      cursor_rows "$ver" >>"$out" || { echo "cursor list failed" >&2; fail=1; }
      changed=1
    else
      grep $'^cursor:' "$TABLE" >>"$out"
    fi
    continue
  fi
  new=$(resolve "$track" "$ver") || { echo "!! $key: cannot resolve version" >&2; echo "$line" >>"$out"; fail=1; continue; }
  if [[ $new == "$ver" && $sum =~ ^[0-9a-f]{64}$ ]] && ((!FORCE)); then
    echo "$line" >>"$out"; continue
  fi
  echo ":: $key ${ver:-(none)} -> $new"
  if res=$(hash_of "$url" "$new"); then
    printf '%s\t%s\t%s\t%s\t%s\n' "$key" "$track" "$new" "${res%%$'\t'*}" "${res##*$'\t'}" >>"$out"
    changed=1
  else
    echo "$line" >>"$out"; fail=1
  fi
done <"$TABLE"

cp "$out" "$TABLE"
((changed)) && echo "Updated $TABLE: review with git diff" || echo "Everything already current."
exit "$fail"
