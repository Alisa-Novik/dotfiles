# Alice's dotfiles

One repository, one terminal workflow, three explicit profiles:

| Profile | Stow packages | Intended machine |
| --- | --- | --- |
| `linux-personal` | `common linux personal` | Personal Linux workstation |
| `macos-personal` | `common macos personal macos-personal` | Personal Mac |
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
- `stow/macos-personal`: the personal Mac desktop only: AeroSpace, Ghostty,
  and the float-only yabai animation helper.
- `launchd`: versioned LaunchAgent templates. Bootstrap installs regular
  copies because current macOS rejects these agents when loaded via symlink.
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

## Personal Mac desktop

AeroSpace owns tiling, fullscreen, and application routing. `Option-F` and
`Control-Command-F` expand the current window inside its AeroSpace workspace
for every application. `Option-1`…`Option-0` switch directly to workspaces
1…10; `Option-Tab` returns to the previous workspace. These actions do not
wait for or restart background helpers. The `aerospace-workspace NUMBER`
command remains as a compatibility alias for the same direct switch.
At startup, AeroSpace selects the terminal workspace once before launching
missing apps in the background; the coordinator never switches it afterward.

Application routing places new windows without focusing them or making them
fullscreen. `Option-Shift-A` balances the current workspace. Rearranging every
workspace is an explicit terminal action: `aerospace-align-windows --reset-all`.
The existing Option navigation and tmux `Control-1`…`Control-9` shortcuts are
preserved. `Control-Shift-X` is available to Kitty again, and service-mode
Backspace no longer closes other windows. Resize and service modes still show
their `R`/`S` indicator in the AeroSpace menu. Escape or Return exits either
mode; Option-number and Option-Tab exit before navigating. Option-R toggles
resize mode.

Native macOS fullscreen, entered through an application's own UI or video
player, remains a separate mode that creates a macOS Space. Leave it through
the application, or press `Option-Shift-F` to leave native fullscreen for the
focused window. The terminal equivalent is
`aerospace-safe-fullscreen --exit-native`. Afterward, `Option-F` can expand the
window inside AeroSpace. Native fullscreen can also stay enabled. Detached
workspace-change and focus-change callbacks inspect leaked Firefox/Discord
snapshots twice while transitions settle. Recovery requires a full-display,
unmanaged, untitled AXUnknown window with no children, no close button, no
fullscreen/minimize/resize controls, and no main/focused status. A normal managed
window from the same app must still exist. Native Space membership and stable
repeated observations protect real fullscreen windows and changing desktops.

The guard moves only that snapshot beyond all active display bounds. It never
hides or activates the owner app, so recovery also works while Discord is in
front and after its old native fullscreen Space has disappeared. This is a
workaround for leaked windows, not a fix to macOS fullscreen transitions.
`aerospace-clear-stale-snapshots --dry-run` explains the current decision without
changing windows; running it without arguments requests the same guarded
recovery. Background results are in `~/.local/state/aerospace-fullscreen.log`.

Switching from native fullscreen to an empty workspace uses
`aerospace-empty-desktop`: a transparent, mouse-ignoring accessory window gives
AppKit a focus target on the ordinary desktop. It has no Dock icon or close
button and AeroSpace excludes it from managed windows. A delayed request is
discarded if the selected workspace changed or gained a window. It does not
exit fullscreen, inject keys, or write native Space state. `Option-6` also
retries the callback when workspace 6 was already selected. Build without
launching anything with `aerospace-empty-desktop --prepare`; the generated app
is cached under `~/Library/Caches/aerospace-empty-desktop/`. Its `--self-test`
mode checks guards without creating windows or querying the live desktop.

Bootstrap disables the old yabai/skhd services and the dedicated yabai
animation helper. Their configuration and helper LaunchAgent template remain
installed for an explicit opt-in or rollback. Normal AeroSpace operation does
not require yabai or a particular Reduce Motion setting. The doctor checks
the desktop scripts and shortcut policy, and bounds optional yabai status
queries so an unresponsive service cannot hang the check. Focus borders are
intentionally disabled.

The personal-Mac bootstrap also disables the hidden
`com.apple.BTMNotificationAgent` notification source. This removes every
“App Background Activity” banner—including ones labelled `sh`, `yabai`, or a
future helper name—without disabling Background Task Management or changing
which background items are allowed. Before changing Notification Center's
preference, bootstrap saves its plist in the normal private backup directory.
