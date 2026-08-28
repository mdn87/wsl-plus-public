# Architecture

## Goals

WSL Plus should make a fresh WSL installation comfortable without making convenience settings authoritative over security policy or an existing agent environment.

The key rule is separation of concerns:

- Core features answer, "What improves interactive use?"
- Site policies answer, "What capability is allowed here?"
- Profile defaults answer, "Which ordinary product behavior is selected?"
- Integrations answer, "What existing behavior must not change?"

## Installation flow

1. Load capability, defaults, and integration files with the restricted key/value parser. Configuration files are never sourced as shell code.
2. Validate the versioned contract of every integration that publishes one, and detect its exact root-owned facts read-only.
3. Reject an ambiguous partial deployment, or a complete deployment of one integration while a different integration is selected.
4. Reject planned WSL Plus writes that intersect an exact protected effect.
5. Validate disabled Windows mount, executable, cross-filesystem, and credential capabilities.
6. Produce an optional deterministic plan ID without invoking APT or writing user/root state.
7. Back up every WSL Plus-owned user path that may change.
8. Run the separately authorized package step, then capture the pre-write shell causality baseline.
9. Install versioned files, schema-2 runtime configuration, the absolute wrapper, and bounded shell/tmux blocks.
10. Compare protected files and enabled/disabled current-shell state.
11. Run `doctor`; a failure restores WSL Plus-owned user files.

## Filesystem layout

```text
~/.local/share/wsl-plus/current/   versioned installed package
~/.config/wsl-plus/                generated runtime configuration
~/.local/state/wsl-plus/           backups and install records
~/.local/bin/wsl-plus              stable absolute wrapper for every profile
~/.local/share/wsl-plus/current/bin/wsl-plus
                                    versioned command used by the shell function
```

The package never replaces `.bashrc` or `.tmux.conf`. It owns only blocks bounded by exact markers.

## Policy and integration composition

The active behavior is the intersection of core features, capability
permission, selected product defaults, and integration effects.

```text
active capability = core feature
                  AND policy allows it
                  AND profile default selects it
                  AND integration does not prohibit it
```

An integration that declares `REQUIRED_POLICY=restricted` cannot be selected under `home`. No integration may flip a denied policy capability to allowed.

## Shell behavior

Under the `restricted` policy, shell initialization deliberately avoids:

- PATH edits
- external Home session adapters
- redefinition of commands an integration marks as owner-protected

Local history hooks, zoxide directory tracking, and an installed ble.sh line
editor are ordinary Linux shell behavior. They stay permitted under
`restricted` because they grant no Windows, credential, repository, or agent
capability. The `restricted` profile leaves the existing prompt unchanged as a
product default.

The package command is exposed through a shell function and an absolute
`~/.local/bin/wsl-plus` artifact. WSL Plus does not add that directory to PATH.

## Local session behavior

Both profiles may enable the bounded native session command and local tmux
fragment. The native backend discovers existing tmux sessions and zoxide
directories, uses fzf for selection, and may create a tmux session at an
existing directory.

Under Home's `auto` backend, an external Sesh binary is optional. WSL Plus
invokes it with a package-owned configuration containing no startup commands,
clone roots, aliases, or worktree behavior. An external tmux-resurrect
installation is also optional, but process restoration is forced off and
save/restore remain manual. The `restricted` profile's `native` backend invokes
neither adapter and rejects save/restore.

Session navigation never claims runtime ownership, restores a process, launches an agent, creates a repository, or edits a worktree.

## Windows bootstrap

`bootstrap.ps1` archives the checked-out package and streams it to a Linux `tar` process through `wsl.exe` standard input. It does not depend on a Windows drive mount in the distro. That matters on a locked-down distro, where `/mnt/c` and Windows executable interop are expected to be unavailable.

The bootstrap does not configure Windows Terminal, WezTerm, WSL automount, interop, credentials, or SSH agents.

## External utility rule

External utilities may be detected behind a policy-gated adapter. They are not downloaded or updated, and they are not allowed to own shell startup, repositories, worktrees, agent lifecycle, credentials, or MCP configuration. The ble.sh adapter is sourced only from known installation paths, uses a package-owned rc file, and owns only interactive line editing while active.

## Ownership boundary

WSL Plus owns local, policy-aware convenience adapters and nothing else. It
does not upgrade, supervise, route, or configure any other tool on the machine.
Where another system already owns a behavior, the integration contract records
that as a protected effect rather than reimplementing it.

## Trust boundary

WSL Plus validates measured capability and protected-effect facts. It does not
use a WSL Plus-created machine lock as policy authority; legacy lock files are
preserved only for explicit migration or removal.

WSL Plus does not claim to distinguish adversarial same-user processes. Where a
site runs a broker or authorization service, that service remains authoritative
for that problem.
