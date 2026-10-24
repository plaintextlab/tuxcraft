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
command -v starship >/dev/null && eval "$(starship init bash)" || PS1='[\u@\h \W]\$ '

# Modern defaults
if command -v eza >/dev/null; then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -lah --icons=auto --git --group-directories-first'
  alias tree='eza -a --icons=auto --tree --git-ignore'
else
  alias ls='ls --color=auto'; alias ll='ls -lah --color=auto'
fi
alias grep='grep --color=auto'
alias cat='bat --paging=never --style=plain'
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
