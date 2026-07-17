# Shared interactive zsh configuration. OS and role are selected by the
# `linux`/`macos` and `personal`/`work` Stow overlays.

typeset -U path PATH
for dotfiles_path_entry in \
	/usr/local/sbin \
	/usr/local/bin \
	/opt/homebrew/sbin \
	/opt/homebrew/bin \
	"$HOME/bin" \
	"$HOME/.local/bin" \
	"$HOME/.npm-global/bin"
do
	if [[ -d "$dotfiles_path_entry" ]]; then
		path=("$dotfiles_path_entry" $path)
	fi
done
unset dotfiles_path_entry

export PATH
export EDITOR=nvim
export VISUAL=nvim
export RIPGREP_CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/config"

if command -v fd >/dev/null 2>&1; then
	export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
elif command -v fdfind >/dev/null 2>&1; then
	export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
elif command -v rg >/dev/null 2>&1; then
	export FZF_DEFAULT_COMMAND='rg --files --hidden --glob !.git'
fi
if [[ -n ${FZF_DEFAULT_COMMAND:-} ]]; then
	export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

if [[ -d "$HOME/.dotfiles" ]]; then
	export DOTFILES_DIR="$HOME/.dotfiles"
elif [[ -d "$HOME/dotfiles" ]]; then
	export DOTFILES_DIR="$HOME/dotfiles"
else
	export DOTFILES_DIR="$HOME/.dotfiles"
fi

DOTFILES_OS=""
DOTFILES_ROLE=""
if [[ -r "$HOME/.config/dotfiles/os" ]]; then
	IFS= read -r DOTFILES_OS < "$HOME/.config/dotfiles/os" || true
fi
if [[ -r "$HOME/.config/dotfiles/role" ]]; then
	IFS= read -r DOTFILES_ROLE < "$HOME/.config/dotfiles/role" || true
fi

# The marker files are authoritative, but keep a useful OS fallback when only
# the common package is installed during bootstrap.
if [[ -z "$DOTFILES_OS" ]]; then
	case "$(uname -s)" in
		Linux) DOTFILES_OS=linux ;;
		Darwin) DOTFILES_OS=macos ;;
		*) DOTFILES_OS=unknown ;;
	esac
fi

case "$DOTFILES_OS-$DOTFILES_ROLE" in
	linux-personal|macos-personal|macos-work)
		export DOTFILES_PROFILE="$DOTFILES_OS-$DOTFILES_ROLE"
		;;
	*)
		export DOTFILES_PROFILE=unconfigured
		if [[ -o interactive && -n "$DOTFILES_ROLE" ]]; then
			print -u2 "dotfiles: unsupported profile $DOTFILES_OS-$DOTFILES_ROLE"
		fi
		;;
esac
export DOTFILES_OS DOTFILES_ROLE

export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_THEME="robbyrussell"
plugins=(git vi-mode)
if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
	source "$ZSH/oh-my-zsh.sh"
else
	bindkey -v
fi

# fzf 0.48+ can emit its own zsh integration. Ubuntu's older package cannot,
# so fall back to the distro-provided scripts when that capability is absent.
if command -v fzf >/dev/null 2>&1; then
	dotfiles_fzf_init=$(fzf --zsh 2>/dev/null) || dotfiles_fzf_init=""
	if [[ -n "$dotfiles_fzf_init" ]]; then
		eval "$dotfiles_fzf_init"
	else
		for dotfiles_fzf_script in \
			/usr/share/doc/fzf/examples/completion.zsh \
			/usr/share/fzf/completion.zsh \
			/usr/share/doc/fzf/examples/key-bindings.zsh \
			/usr/share/fzf/key-bindings.zsh
		do
			[[ -r "$dotfiles_fzf_script" ]] && source "$dotfiles_fzf_script"
		done
		unset dotfiles_fzf_script
	fi
	unset dotfiles_fzf_init
fi

alias cdd='cd -- "$DOTFILES_DIR"'
alias kc='"$EDITOR" "$HOME/.config/kitty/kitty.conf"'
alias nc='"$EDITOR" "$HOME/.config/nvim/init.lua"'
alias nv='nvim'
alias nz='"$EDITOR" "$HOME/.zshrc"'
alias ns='source "$HOME/.zshrc"'
alias cdw='cd -- "$HOME/projects"'
alias mct='mvn clean test'
alias mci='mvn clean install'

export HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
export HISTSIZE=100000
export SAVEHIST=100000
setopt AUTO_CD EXTENDED_HISTORY SHARE_HISTORY APPEND_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_VERIFY

if [[ "$DOTFILES_PROFILE" != unconfigured && -r "$HOME/.config/dotfiles/zsh/profile.zsh" ]]; then
	source "$HOME/.config/dotfiles/zsh/profile.zsh"
fi

# >>> cento init >>>
if [[ "$DOTFILES_ROLE" == personal && -f "$HOME/.config/cento/init.zsh" ]]; then
	source "$HOME/.config/cento/init.zsh"
fi
# <<< cento init <<<

# Machine-local and work-only environment belongs outside the repository.
if [[ -r "$HOME/.config/dotfiles/local.zsh" ]]; then
	source "$HOME/.config/dotfiles/local.zsh"
fi
