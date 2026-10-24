# ~/.bash_profile — login shells read this; keep everything in ~/.bashrc.
[[ -d ~/.local/bin ]] && PATH="$HOME/.local/bin:$PATH"
[[ -f ~/.bashrc ]] && . ~/.bashrc
