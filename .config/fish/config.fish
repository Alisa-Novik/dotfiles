export VISUAL="nvim"

export fish_color_cwd 87d7ff
export fish_color_user F08080

alias s="./setup.sh"

alias tg="~/Telegram/Telegram"
alias cdd="cd ~/dotfiles"
alias cda="cd ~/projects/Alisa-Novik.github.io/articles/"
alias kc="nv ~/.config/kitty/kitty.conf"
alias nc="nv ~/.config/nvim/init.lua"
alias fc="nv ~/.config/fish/config.fish"
alias fs="source ~/.config/fish/config.fish"
alias i3="nvim ~/.config/i3/config"
alias nv=nvim
alias cdw="cd ~/projects/"
alias cdl="cd ~/projects/lox/"
alias cdg="cd ~/projects/golab/"
alias mct="mvn clean test"
alias mci="mvn clean install"
alias oci="/home/alice/bin/oci"
alias conn="bluetoothctl connect BC:87:FA:C2:C6:91"
alias aiv="source ~/projects/aistuff/bin/activate.fish"
alias cl="./cl"


# Kanagawa-inspired Fish shell colors

# Syntax Highlighting
set -g fish_color_normal normal
set -g fish_color_command 7E9CD8  # crystalBlue
set -g fish_color_keyword 957FB8  # oniViolet
set -g fish_color_quote 98BB6C    # springGreen
set -g fish_color_redirection 7AA89F  # waveAqua2
set -g fish_color_end 658594      # dragonBlue
set -g fish_color_error E82424    # samuraiRed
set -g fish_color_param DCA561    # autumnYellow
set -g fish_color_comment 727169  # fujiGray
set -g fish_color_selection --background=2D4F67 --foreground=DCD7BA  # waveBlue2 and fujiWhite

# Autosuggestions
set -g fish_color_autosuggestion 54546D  # sumiInk4

# Command history search (Ctrl+R)
set -g fish_color_search_match --background=223249 --foreground=DCD7BA  # waveBlue1 and fujiWhite

# Pager colors (used in tab completions)
set -g fish_pager_color_progress 6A9589  # waveAqua1
set -g fish_pager_color_prefix 7E9CD8 --bold  # crystalBlue
set -g fish_pager_color_completion DCD7BA  # fujiWhite
set -g fish_pager_color_description 938AA9  # springViolet1


for v in fish_color_user fish_color_host fish_color_host_remote
    set -eg $v        # erase any blank global value
    set -U  $v normal # write a safe universal fallback
end

# opencode
fish_add_path /home/alice/.opencode/bin
