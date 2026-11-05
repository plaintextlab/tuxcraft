# ~/.bashrc — tuxcraft (from debi3n, made distro-neutral)
[[ $- != *i* ]] && return

HISTSIZE=50000 HISTFILESIZE=100000 HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize autocd globstar cdspell
export EDITOR=micro VISUAL=micro PAGER=less MANPAGER="less -R"

[[ -f ~/.config/tuxcraft/env.sh ]] && . ~/.config/tuxcraft/env.sh
[[ -f /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion

# fzf keybindings: Ctrl-R history, Ctrl-T files, Alt-C cd
if command -v fzf >/dev/null; then
  eval "$(fzf --bash 2>/dev/null)" || for f in /usr/share/fzf/key-bindings.bash /usr/share/doc/fzf/examples/key-bindings.bash; do [[ -f $f ]] && . "$f"; done
fi
command -v zoxide   >/dev/null && eval "$(zoxide init bash --cmd cd)"
# A slow directory scan just skips the language modules; don't print [WARN] lines above the prompt.
export STARSHIP_LOG=error
# Inside a distrobox/toolbox container without its own starship, borrow the host's (/run/host).
[[ -f /run/.containerenv ]] && ! command -v starship >/dev/null && [[ -x /run/host/usr/bin/starship ]] &&
  starship() { /run/host/usr/bin/starship "$@"; }
if command -v starship >/dev/null; then eval "$(starship init bash)"
else
  _ctr=${CONTAINER_ID:-}; [[ -z $_ctr && -f /run/.containerenv ]] && _ctr=$(sed -n 's/^name="\(.*\)"/\1/p' /run/.containerenv)
  PS1="${_ctr:+\[\e[1;30;43m\] $_ctr \[\e[0m\] }[\u@\h \W]\$ "; unset _ctr
fi

# kitty sets TERM=xterm-kitty; hosts/containers without its terminfo (ssh, distrobox) get a safe one.
[[ $TERM == xterm-kitty ]] && ! infocmp xterm-kitty >/dev/null 2>&1 && export TERM=xterm-256color
# img: show pictures in the terminal (real images in kitty, block art elsewhere, e.g. over ssh)
img() { chafa --align mid,mid "$@"; }
# rmpc needs mpd running; start it first (no-op when it already runs)
rmpc() { command -v tux-music >/dev/null && tux-music start; command rmpc "$@"; }

# Modern defaults
if command -v eza >/dev/null; then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -lah --icons=auto --git --group-directories-first'
  alias tree='eza -a --icons=auto --tree --git-ignore'
else
  alias ls='ls --color=auto'; alias ll='ls -lah --color=auto'
fi
alias grep='grep --color=auto'
command -v bat >/dev/null && alias cat='bat --paging=never --style=plain'
alias df='df -h' du='du -h' free='free -h'
alias disk='ncdu -x /'
alias lg='lazygit'
alias rm='trash-put'          # recoverable: trash-list / trash-restore
alias rmf='command rm'

# Packages: one vocabulary on every distro (see `tux-pkg --help`)
alias ii='tux-pkg install' rr='tux-pkg remove' ss='tux-pkg search' up='sysup'

# fo: fuzzy-open a file in $EDITOR (from debi3n)
fo() {
  local file
  file=$(fd --type f --hidden --exclude .git . "${1:-.}" 2>/dev/null | fzf --preview 'bat --style=numbers --color=always {} 2>/dev/null || cat {}')
  [[ -n $file ]] && "${EDITOR:-micro}" "$file"
}

# y: yazi that cd's to the last directory on exit
y() {
  local tmp cwd; tmp=$(mktemp -t yazi-cwd.XXXXXX)
  yazi "$@" --cwd-file="$tmp"
  cwd=$(cat -- "$tmp" 2>/dev/null) && [[ -n $cwd && $cwd != "$PWD" ]] && builtin cd -- "$cwd"
  command rm -f -- "$tmp"
}

[[ -f ~/.bashrc.local ]] && . ~/.bashrc.local
