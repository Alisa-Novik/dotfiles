# codex-deck.nvim

Status: parked idea; revisit after the cross-platform dotfiles migration.

## Goal

Build a small Neovim plugin that treats Codex threads like Harpoon treats files:
pinned, numbered, project-scoped lanes with a persistent Markdown composer and
transcript.

## Smallest useful version

- Harpoon-style slots containing `cwd`, `thread_id`, prompt buffer, transcript
  buffer, status, and sandbox mode.
- Submit a prompt through stdin with `codex exec --json -`.
- Capture the exact thread id from `thread.started` and continue with
  `codex exec resume THREAD_ID --json -`.
- Run commands with `vim.system()` and argv arrays, never interpolated shell
  strings.
- Keep separate explicit `Ask` (`read-only`) and `Apply` (`workspace-write`)
  actions.
- Stream JSONL into a read-only Markdown transcript and expose cancellation.
- Add current selection, buffer, diagnostics, quickfix items, or selected
  Harpoon paths as optional context.
- Persist lane metadata per git root under XDG state rather than inside the
  project.

## Possible keys

- `<leader>ca`: pin/add a Codex lane.
- `<leader>c1` through `<leader>c5`: select a lane.
- `<leader>ce`: open its composer.
- `<C-s>`: submit.
- `<C-c>`: cancel.
- `[c` / `]c`: navigate changed hunks.

## Later ideas

- Running/waiting/done indicators in Neovim and tmux.
- One git worktree per lane for safe parallel agents.
- Telescope prompt history.
- App-server backend for steering, interrupts, and interactive approvals.

## Existing projects worth revisiting

- https://github.com/shabaraba/vibing.nvim
- https://github.com/jyhl/sift.nvim
- https://github.com/eetann/editprompt
- https://github.com/milanglacier/yarepl.nvim
- https://github.com/folke/sidekick.nvim

Codex primitives:

- https://learn.chatgpt.com/docs/non-interactive-mode
- https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md
