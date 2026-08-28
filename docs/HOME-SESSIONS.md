# Local session navigation

Local session navigation provides fast access to persistent tmux workspaces
without turning WSL Plus into an agent or repository orchestrator.

Both shipped profiles enable bounded native tmux navigation. Home selects the
`auto` backend and may use already installed optional adapters. `restricted`
selects the `native` backend and never invokes Sesh or tmux-resurrect.

## Commands

```bash
wsl-plus session                 # interactive picker
wsl-plus session list            # discoverable sessions and directories
wsl-plus session attach NAME     # existing tmux session
wsl-plus session create DIR      # existing directory
wsl-plus session open TARGET     # existing tmux session or directory
wsl-plus session last            # previous tmux session
wsl-plus session status          # installed backend report
wsl-plus session save            # Home auto backend only
wsl-plus session restore         # Home auto backend only
```

The shell helper `wslp-session` forwards to the same command.

Inside tmux:

- `prefix + T` opens the picker in a popup.
- `prefix + L` switches to the previous tmux session.

## Native backend

The built-in backend uses normal local tools:

- tmux sessions
- zoxide directory history when available
- fzf selection

Opening an existing directory creates or attaches to a tmux session named from
the Git root or directory name. Passive Git-root naming is read-only. The
command does not clone, create, or mutate repositories or worktrees; create a
project directory; run project startup commands; or launch an agent.

## Optional Sesh backend

Under the Home `auto` backend, WSL Plus prefers an already available `sesh`
picker. WSL Plus invokes Sesh with:

```text
core/session/sesh.toml
```

That configuration intentionally defines no startup commands, aliases, clone roots, or worktree behavior. Set `WSL_PLUS_SESH_CONFIG` only when deliberately opting into another Home configuration.

WSL Plus does not download or update Sesh. Follow the upstream project installation instructions, then run:

```bash
wsl-plus session status
```

Upstream project: <https://github.com/joshmedeski/sesh>

## Optional tmux-resurrect backend

WSL Plus detects a manual installation at:

```text
~/.tmux/plugins/tmux-resurrect
```

A standard manual installation is:

```bash
git clone https://github.com/tmux-plugins/tmux-resurrect \
  ~/.tmux/plugins/tmux-resurrect
```

The Home tmux configuration sets:

```tmux
set -g @resurrect-processes 'false'
```

This preserves layouts and working directories while refusing program restoration. Agent CLIs, shells running privileged commands, development servers, and other processes are not relaunched from a saved layout.

Saving and restoring remain manual and Home-only. The `restricted` profile's
native backend rejects both commands even if tmux-resurrect is installed. WSL Plus does not
install tmux-continuum, automatically save sessions, automatically restore at
boot, or start tmux during machine startup.

Upstream project: <https://github.com/tmux-plugins/tmux-resurrect>

## Deferred session tools

- `tmuxp` remains deferred until repeatable multi-window layouts are being rebuilt by hand often enough to justify configuration files.
- Zellij remains a separate Home experiment. It is not installed or configured by WSL Plus because it would introduce a second session architecture.
