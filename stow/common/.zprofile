# Portable login-shell environment shared by Linux and macOS.
typeset -U path PATH

# Iterate in reverse priority order because each entry is prepended.
for dotfiles_path_entry in \
	/usr/local/sbin \
	/usr/local/bin \
	/opt/homebrew/sbin \
	/opt/homebrew/bin \
	"$HOME/bin" \
	"$HOME/.local/bin"
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
