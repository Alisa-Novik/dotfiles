# Personal aliases and integrations shared by personal Linux and Mac nodes.
if [[ -d "$HOME/.openclaw/bin" ]]; then
	path=("$HOME/.openclaw/bin" $path)
fi

alias cda='cd -- "$HOME/projects/Alisa-Novik.github.io/articles"'
alias cdl='cd -- "$HOME/projects/lox"'
alias cdg='cd -- "$HOME/projects/golab"'
alias oci='"$HOME/bin/oci"'
alias cl='./cl'
alias bd='cento bd'
alias bdd='cento bdd'

if [[ "$DOTFILES_OS" == linux ]]; then
	alias conn='bluetoothctl connect BC:87:FA:C2:C6:91'
	alias tg='"$HOME/Telegram/Telegram"'
	alias i3='"$EDITOR" "$HOME/.config/i3/config"'
	alias golab-l2='pkill -x golab 2>/dev/null || true; sleep 0.2; i3-msg "workspace L2"; cd "$HOME/projects/golab" && setsid -f ./bin/golab >/tmp/golab-l2.log 2>&1'
fi
