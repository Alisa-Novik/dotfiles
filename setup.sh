#!/usr/bin/bash

# Install musthave software
sudo apt-get install -y kitty fish polybar tmux gcc make unzip picom rofi \
				build-essential ripgrep fd-find xclip fonts-noto-color-emoji \
				ninja-build gettext cmake unzip curl 

# Link dotfiles
ln -s ~/dotfiles/.config/i3/config ~/.config/i3/config

ln -s ~/dotfiles/.config/nvim/init.lua ~/.config/nvim/init.lua
ln -s ~/dotfiles/.config/fish/ ~/.config/fish
ln -s ~/dotfiles/.config/kitty/ ~/.config/kitty
ln -s ~/dotfiles/.config/polybar/ ~/.config/polybar
ln -s ~/dotfiles/.config/picom/ ~/.config/picom

git config --global alias.co checkout
git config --global alias.ci commit
git config --global alias.st status
