# Cross-machine migration

The migration is intentionally two phase: inspect first, switch links second.

## Before applying

1. Commit or separately back up anything important on the machine.
2. Clone this repository as `~/.dotfiles`.
3. Run `./bin/bootstrap --profile PROFILE --dry-run`.
4. Read every reported conflict. The work Mac should use `macos-work` and must
   keep company identity/configuration in the local override files.
5. Run `--apply` only when the profile and backup destination look correct.

On apply, conflicting regular files and symlinks are moved to:

```text
~/.local/state/dotfiles/backups/YYYYMMDDTHHMMSSZ/
```

Directory symlinks such as the old `~/.config/nvim -> ~/dotfiles-macos/...`
are backed up as links *and* copied as dereferenced contents before removal.
Kitty's current theme and local theme files are restored into the new real
configuration directory.

## Personal Mac

The old active `~/dotfiles-macos` directory was not a Git repository. Do not
delete it during the first migration. Apply `macos-personal`, run the doctor,
then compare its backup with the new shared configuration. The canonical Nvim
graph is the newer Linux graph; the useful Mac prose and Kitty behavior has
already been merged.

## Work Mac

The work Mac is deliberately isolated by the `work` overlay:

- no Cento or OpenClaw sourcing;
- no personal project aliases;
- no personal Git identity;
- roots limited to `~/work` and `~/projects`;
- company values go in mode-600 local files and never in this repository.

Because the work Mac is not currently registered as a Cento node, begin with
the dry-run and retain its backup receipt for later reconciliation.

## Validation

Run:

```bash
./bin/dotfiles-doctor
```

It checks profile markers, Stow links, commands, zsh syntax, an isolated tmux
server, Neovim headless startup/netrw/Harpoon, the sessionizer, Kitty wrapper
boundaries, Cento markers on personal profiles, local file permissions, and
repository dirt.
