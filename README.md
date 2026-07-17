# Alice's dotfiles

One repository, one terminal workflow, three explicit profiles:

| Profile | Stow packages | Intended machine |
| --- | --- | --- |
| `linux-personal` | `common linux personal` | Personal Linux workstation |
| `macos-personal` | `common macos personal` | Personal Mac |
| `macos-work` | `common macos work` | Work Mac |

The portable core owns zsh, tmux, Neovim, Kitty base settings, ripgrep,
`tmux-sessionizer`, and Git defaults. OS and role packages only provide small
overlays. Company settings, credentials, tokens, private paths, and Cento's
generated state stay outside Git.

## Install

Clone to the same path everywhere:

```bash
git clone https://github.com/Alisa-Novik/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./bin/bootstrap --profile linux-personal --dry-run
./bin/bootstrap --profile linux-personal --apply
./bin/dotfiles-doctor
```

Use `macos-personal` or `macos-work` on the Macs. Package installation is a
separate, explicit action:

```bash
./bin/bootstrap --profile macos-personal --apply --install-packages
```

The work Mac is intentionally outside the Cento registry. Bootstrap it locally
from this public GitHub repository, never use `--with-cento`, and select only
the isolated work profile:

```bash
git clone https://github.com/Alisa-Novik/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./bin/bootstrap --profile macos-work --dry-run
./bin/bootstrap --profile macos-work --apply
./bin/dotfiles-doctor
```

The installer never silently adopts an existing file. On `--apply`, every
conflict is moved into a timestamped private directory under
`~/.local/state/dotfiles/backups/` before Stow creates links.

## Ownership boundaries

- `stow/common`: portable source of truth.
- `stow/linux` / `stow/macos`: mutually exclusive OS fragments.
- `stow/personal` / `stow/work`: mutually exclusive role fragments.
- `~/.config/dotfiles/local.zsh`, `tmux/local.conf`, `nvim/local.lua`, and
  `~/.config/git/local.inc`: untracked local or work-only settings.
- `~/.config/kitty/kitty.conf`, `current-theme.conf`, and copied Cento themes:
  local runtime state. The wrapper includes the Stow-owned `dotfiles.conf`.
- `~/.config/cento/*`: generated and owned by Cento. The tracked zsh/tmux
  entrypoints contain guarded source markers only for personal profiles.
- The work Mac is never a Cento node. Its `macos-work` profile is installed
  locally from GitHub and contains no Cento/OpenClaw or personal state.

Neovim intentionally uses built-in netrw (`<leader>e`, `<C-e>`) and keeps
Harpoon 2. Ripgrep defaults live in `~/.config/ripgrep/config`. In tmux,
`prefix + f` opens `tmux-sessionizer` in a popup.

The existing i3/Polybar/Picom files remain tracked as a legacy Linux desktop
layer, but the cross-platform bootstrap intentionally does not install them.
Cento currently mutates parts of that desktop layer, so it should be migrated
behind the same wrapper boundary in a separate change.

See [docs/migration.md](docs/migration.md) before adopting an already-diverged
machine.
