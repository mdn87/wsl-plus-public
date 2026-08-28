# WSL Plus

A reinstallable quality-of-life layer for Windows Subsystem for Linux that
keeps terminal conveniences separate from security policy.

Most WSL dotfile setups assume the machine is yours to configure. That
assumption breaks on a distro that something else already governs — a managed
build, an agent sandbox, a broker that owns particular files and command names.
WSL Plus is built for both cases at once: it installs the same conveniences,
but what it is *permitted* to do is a separate, declared, testable layer.

## The idea

Four independent layers, each answering one question:

| Layer | Question it answers |
| --- | --- |
| `core/` | What improves interactive use? |
| `policies/` | What capability is permitted here? |
| `defaults/` | Which ordinary product behavior is selected? |
| `integrations/` | What existing behavior must not change? |

An integration may **narrow** a policy. It can never widen one. A convenience
default is never allowed to become a policy decision by accident.

Two policies ship:

- **`home`** — an ordinary personal distro. Windows mounts, clipboard bridges,
  app launchers, and persistent session adapters are all permitted.
- **`restricted`** — a contained distro. Windows interop, drive mounts,
  cross-filesystem access, credential bridges, shared SSH agents, cloud
  history, and Windows PATH import are all denied. Neutral shell improvements
  are still available, because they grant none of those capabilities.

`restricted` is checked, not imposed. If the distro still has `/mnt/c` or a
reachable `cmd.exe`, the installer refuses and writes nothing, rather than
editing `/etc/wsl.conf` to make the policy true. Contain the distro first —
see [Policy preflight](docs/INSTALLATION.md#policy-preflight).

## Integration contracts

The part worth stealing. An integration can publish a **contract** — a
versioned, hash-pinned directory declaring exactly what it owns:

```text
integrations/<id>/contracts/v1/
  contract.conf         schema, owner repo, owner commit, policy commit, hashes
  effects.tsv           exact protected files, commands, authorization lanes
  detection-facts.tsv   root-owned facts that prove this site is deployed here
  SHA256SUMS            covers exactly the three files above
```

Before it writes anything, the installer:

1. Validates the contract's schema, its checksum manifest, its owner baseline
   commit, and a separate publication commit pin.
2. Rejects a contract directory with extra entries, symlinks, wrong file modes,
   or a tampered hash.
3. Reads the detection facts of every integration you did **not** select. If
   another integration's facts are all present on this machine, your selection
   is refused as a misclassification. A partial fact set is ambiguous and also
   refused — before any mutation.
4. Refuses any planned write whose path intersects a declared protected effect.

`integrations/example-site/` is a complete worked example that exercises the
whole path against fictional targets. Copy it to write your own — see
[docs/INTEGRATIONS.md](docs/INTEGRATIONS.md).

## Install

From Windows, the bootstrap streams the package through `wsl.exe` standard
input, so it works even on a distro with no `/mnt/c` and no Windows interop:

```powershell
.\bootstrap.ps1 -Distro Ubuntu -Policy home
```

```powershell
.\bootstrap.ps1 -Distro Ubuntu -Policy restricted
```

From inside WSL:

```bash
./install.sh --policy home --integration plain-wsl
```

Add `--skip-packages` when APT packages are managed separately. Add `--check`
for a deterministic, zero-mutation preview; feeding the printed ID back with
`--apply-plan` verifies that nothing changed in between. No profile requires
that ceremony.

## Commands

```bash
wsl-plus doctor        # policy and integration drift check
wsl-plus version
wsl-plus rollback      # restore the last transaction
```

Every profile installs a stable absolute wrapper at `~/.local/bin/wsl-plus` and
exposes the same absolute command through a marker-bounded interactive shell
function. WSL Plus does not add `~/.local/bin` to your PATH.

Local session navigation, under both profiles:

```bash
wsl-plus session               # interactive picker
wsl-plus session list
wsl-plus session attach NAME
wsl-plus session create DIRECTORY
wsl-plus session last
wsl-plus session status
```

Inside tmux, `prefix + T` opens the picker and `prefix + L` switches to the
last session. Home-only helpers (`wslp-open`, `wslp-clip-copy`,
`wslp-clip-paste`, `wslp-cdrive`, and friends) exist only where the policy
permits the capability behind them.

## What it does

- Marker-bounded, idempotent Bash and tmux installation — it never replaces
  `.bashrc` or `.tmux.conf`, only blocks it owns.
- Inline suggestions through a **detected** ble.sh install, with a
  package-owned rc file and version-appropriate settings.
- fzf key bindings and completion, zoxide, and namespaced navigation, archive,
  `bat`, and `fd` helpers, each gated on policy.
- Additive tmux defaults: persistent history, mouse support, pane helpers.
- Bounded native tmux session navigation with no external dependency; optional
  Sesh and tmux-resurrect adapters under `home` only, with process restoration
  forced off.
- Optional Windows SSH-agent relay under `home`, never configured or started
  automatically.
- Causal comparison of protected files, command resolution, and interactive
  shell PATH — the installer proves *it* caused a change before failing.
- Transaction backups, automatic restore on failure, and manual rollback.

## What it deliberately does not do

- Download or update ble.sh, Sesh, tmux-resurrect, or any external utility. It
  detects what you installed.
- Touch Windows Terminal, WezTerm, `/etc/wsl.conf`, `.wslconfig`,
  `/etc/resolv.conf`, VPN routes, or firewall rules.
- Create a root-owned machine policy lock. A lock written by an older build is
  preserved byte-for-byte, reported as deprecated, and removed only by explicit
  request.
- Add anything to PATH.
- Claim to distinguish adversarial same-user processes. Where a site runs a
  broker, that broker stays authoritative.

## Requirements

Bash on Ubuntu or Debian WSL. APT is the only package adapter that exists; the
configuration model leaves room for `dnf` and `pacman`, but nobody has written
them.

The test suite needs `bash`, `git`, and util-linux `script`. ShellCheck is used
when present.

```bash
./tests/run.sh
```

## Documentation

| Document | Contents |
| --- | --- |
| [Architecture](docs/ARCHITECTURE.md) | Layer separation, install flow, trust boundary |
| [Policy model](docs/POLICY-MODEL.md) | Authority order, configuration ownership, shipped profiles |
| [Installation](docs/INSTALLATION.md) | Options, ble.sh setup, check/apply, rollback |
| [Integrations](docs/INTEGRATIONS.md) | Writing a contract-backed integration |
| [Local sessions](docs/HOME-SESSIONS.md) | Session navigation and its limits |
| [Home network recovery](docs/HOME-NETWORK-RECOVERY.md) | WSL DNS/VPN troubleshooting runbook |
| [Roadmap](docs/ROADMAP.md) | What is deferred and why |

## A note on repositories

Cross-filesystem access does not imply multi-writer Git access. Do not let
Windows Git, WSL Git, a sync daemon, and an agent concurrently mutate the same
checkout. Keep one authoritative working tree per repository and treat the
other filesystem views as access paths, not additional owners.

## License

MIT — see [LICENSE](LICENSE).
