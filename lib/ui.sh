# shellcheck shell=bash
# Plain-bash terminal UI: no dialog/whiptail/gum needed, so it runs on any live ISO.
# Every prompt writes its answer into a named variable. If that variable is already
# set (from --config answers file) the prompt is skipped, which makes installs repeatable.

if [[ -t 1 ]]; then
  C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
  C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m' C_CYAN=$'\e[36m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN=''
fi

TUX_LOG=${TUX_LOG:-/var/log/tuxcraft.log}

_log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$TUX_LOG" 2>/dev/null || true; }
info() { _log "INFO  $*"; printf '%s::%s %s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$*"; }
ok()   { _log "OK    $*"; printf '%s ✓%s %s\n' "$C_GREEN$C_BOLD" "$C_RESET" "$*"; }
warn() { _log "WARN  $*"; printf '%s !%s %s\n' "$C_YELLOW$C_BOLD" "$C_RESET" "$*" >&2; }
die()  { _log "FATAL $*"; printf '%s ✗ %s%s\n' "$C_RED$C_BOLD" "$*" "$C_RESET" >&2; exit 1; }
step() { _log "STEP  $*"; printf '\n%s==> %s%s\n' "$C_CYAN$C_BOLD" "$*" "$C_RESET"; }

banner() {
  printf '%s' "$C_CYAN$C_BOLD"
  cat <<'EOF'
  _                            __ _
 | |_ _   ___  _____ _ __ __ _/ _| |_
 | __| | | \ \/ / __| '__/ _` | |_| __|
 | |_| |_| |>  < (__| | | (_| |  _| |_
  \__|\__,_/_/\_\___|_|  \__,_|_|  \__|
EOF
  printf '%s  one script, a working i3/sway desktop%s\n\n' "$C_RESET$C_DIM" "$C_RESET"
}

# _isset VAR -> true if VAR was preset (answers file / env)
_isset() { [[ -n "${!1:-}" ]]; }

# ask VAR "Question" [default]
ask() {
  local __var=$1 __q=$2 __def=${3:-} __ans
  _isset "$__var" && return 0
  [[ -n "${TUX_YES:-}" && -n "$__def" ]] && { printf -v "$__var" '%s' "$__def"; return 0; }
  while :; do
    read -r -e -p "${C_BOLD}? ${__q}${C_RESET}${__def:+ ${C_DIM}[$__def]${C_RESET}} " __ans </dev/tty || die "No terminal input"
    __ans=${__ans:-$__def}
    [[ -n "$__ans" ]] && break
  done
  printf -v "$__var" '%s' "$__ans"
}

# ask_secret VAR "Question"  (asks twice)
ask_secret() {
  local __var=$1 __q=$2 __a __b
  _isset "$__var" && return 0
  while :; do
    read -r -s -p "${C_BOLD}? ${__q}${C_RESET} " __a </dev/tty; echo
    read -r -s -p "${C_BOLD}? Repeat:${C_RESET} " __b </dev/tty; echo
    [[ -n "$__a" && "$__a" == "$__b" ]] && break
    warn "Empty or not matching, try again."
  done
  printf -v "$__var" '%s' "$__a"
}

# confirm "Question" [y|n] -> exit status
confirm() {
  local q=$1 def=${2:-y} ans hint
  [[ -n "${TUX_YES:-}" ]] && [[ $def == y ]] && return 0
  [[ $def == y ]] && hint='[Y/n]' || hint='[y/N]'
  read -r -p "${C_BOLD}? ${q}${C_RESET} ${C_DIM}${hint}${C_RESET} " ans </dev/tty || ans=''
  ans=${ans:-$def}
  [[ ${ans,,} == y* ]]
}

# choose VAR "Title" default_key "key|Label|description" ...
choose() {
  local __var=$1 __title=$2 __def=$3; shift 3
  local -a keys=()
  local i=1 n item key label desc defn=1
  if _isset "$__var"; then return 0; fi
  if [[ -n "${TUX_YES:-}" ]]; then printf -v "$__var" '%s' "$__def"; return 0; fi
  printf '\n%s%s%s\n' "$C_BOLD" "$__title" "$C_RESET"
  for item in "$@"; do
    IFS='|' read -r key label desc <<<"$item"
    keys+=("$key")
    [[ $key == "$__def" ]] && defn=$i
    printf '  %s%2d)%s %-28s %s%s%s\n' "$C_CYAN" "$i" "$C_RESET" "$label" "$C_DIM" "$desc" "$C_RESET"
    ((i++))
  done
  while :; do
    read -r -p "${C_BOLD}? Choice${C_RESET} ${C_DIM}[$defn]${C_RESET} " n </dev/tty || n=''
    n=${n:-$defn}
    if [[ $n =~ ^[0-9]+$ ]] && ((n >= 1 && n <= ${#keys[@]})); then
      printf -v "$__var" '%s' "${keys[n-1]}"; return 0
    fi
    warn "Enter a number between 1 and ${#keys[@]}."
  done
}

# checklist VAR "Title" "key|Label|on|description" ...   -> VAR="key1 key2 ..."
checklist() {
  local __var=$1 __title=$2; shift 2
  local -a keys=() labels=() descs=() state=()
  local item key label st desc i n mark
  if _isset "$__var"; then return 0; fi
  for item in "$@"; do
    IFS='|' read -r key label st desc <<<"$item"
    keys+=("$key"); labels+=("$label"); descs+=("$desc"); state+=("$st")
  done
  if [[ -z "${TUX_YES:-}" ]]; then
    while :; do
      printf '\n%s%s%s %s(type numbers to toggle, e.g. "2 5", Enter when done)%s\n' "$C_BOLD" "$__title" "$C_RESET" "$C_DIM" "$C_RESET"
      for i in "${!keys[@]}"; do
        if [[ ${state[i]} == on ]]; then mark="${C_GREEN}[x]${C_RESET}"; else mark='[ ]'; fi
        printf '  %s%2d)%s %s %-24s %s%s%s\n' "$C_CYAN" "$((i+1))" "$C_RESET" "$mark" "${labels[i]}" "$C_DIM" "${descs[i]}" "$C_RESET"
      done
      read -r -p "${C_BOLD}? Toggle${C_RESET} " n </dev/tty || n=''
      [[ -z "$n" ]] && break
      for i in $n; do
        [[ $i =~ ^[0-9]+$ ]] && ((i >= 1 && i <= ${#keys[@]})) || continue
        [[ ${state[i-1]} == on ]] && state[i-1]=off || state[i-1]=on
      done
    done
  fi
  local out=''
  for i in "${!keys[@]}"; do [[ ${state[i]} == on ]] && out+="${keys[i]} "; done
  printf -v "$__var" '%s' "${out% }"
}

# has_word "list" word
has_word() { [[ " $1 " == *" $2 "* ]]; }
