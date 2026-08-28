# Installation details

## Windows bootstrap

`bootstrap.ps1` requires Windows, WSL, and `tar.exe`. It packages the current checkout, streams it through `wsl.exe`, and runs the Linux installer from:

```text
~/.local/share/wsl-plus/bootstrap/current
```

Because transfer uses standard input, the distro does not need `/mnt/c` or Windows executable interop.

## Linux installer options

```text
--policy home|restricted
--integration plain-wsl|example-site
--mode managed|augment
--check
--apply-plan SHA256
--skip-packages
```

The supported package manager is APT. Base packages are required when the package step is enabled. Optional packages are installed only when the configured APT repository exposes them.

When `--skip-packages` is used, `doctor` still checks the commands required by
enabled features. It reports available commands normally and warns only when an
enabled command is actually missing.

ble.sh is a detected adapter rather than an APT dependency because Ubuntu and
Debian do not consistently package it. When it exists at
`~/.local/share/blesh/ble.sh`, `/usr/local/share/blesh/ble.sh`, or
`/usr/share/blesh/ble.sh`, WSL Plus enables inline suggestions automatically
with its package-owned configuration. The normal installer never downloads or
updates ble.sh.

Installing ble.sh from source requires Git, GNU make, and GNU awk. Install the
build prerequisites, then install ble.sh into the user-local path:

```bash
sudo apt-get update
sudo apt-get install --yes git make gawk
mkdir -p "$HOME/.local/src"
git clone --recursive --depth 1 --shallow-submodules \
  https://github.com/akinomyoga/ble.sh.git \
  "$HOME/.local/src/ble.sh"
git -C "$HOME/.local/src/ble.sh" rev-parse HEAD
make -C "$HOME/.local/src/ble.sh" install PREFIX="$HOME/.local"
```

Record the printed revision for reproducibility. Do not append a separate
ble.sh `source` command to `.bashrc`; the marker-bounded WSL Plus block loads
the detected adapter with the package-owned configuration. That configuration
uses the installed ble.sh version's automatic history source and subdued
suggestion/error faces while preserving the existing prompt.

The local session command is installed as part of WSL Plus. Sesh and
tmux-resurrect are optional Home adapters and are never downloaded by the
installer. The `restricted` profile uses the native backend only.

## Policy preflight

The installer verifies that the distro already matches the policy. It never
edits WSL's own configuration to make a policy fit. Installing `restricted` on
a distro that still has Windows drive mounts or reachable Windows executables
fails before anything is written:

```text
[wsl-plus] ERROR: Policy preflight failed: Windows executable interop is available: /mnt/c/Windows/system32/cmd.exe ...
```

Contain the distro first, from inside it:

```bash
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[automount]
enabled = false

[interop]
enabled = false
appendWindowsPath = false
EOF
```

Then run `wsl --shutdown` from Windows and start the distro again. Both
`/mnt/c` and `cmd.exe` must be gone before `--policy restricted` will install.

The ordering is deliberate. WSL Plus reports what the machine is; it does not
quietly reconfigure the boundary it is supposed to respect. The same rule is
why the `home` policy is refused on a machine whose deployment facts match an
integration you did not select.

## Optional check/apply

The plan ID includes:

- package version
- selected policy, integration, and mode
- user and home directory
- current `.bashrc` and `.tmux.conf` hashes
- `/etc/wsl.conf` hash
- deprecated machine lock hash, if one already exists
- policy, defaults, integration, and protected-effects contract hashes
- protected path state
- protected command and PATH state

A change between check and apply produces a different plan ID, so a supplied
`--apply-plan` value is rejected. The preview is optional for every profile; no
profile requires it. `--check` does not invoke APT or write user/root state.

The `restricted` profile enables `core/tmux/local-sessions.conf` with the
native backend. It does not source `core/tmux/home-sessions.conf` and rejects
Sesh/tmux-resurrect operations.

## Rollback

Each installation backs up every user-level path it may alter. On an installer or doctor failure, the transaction restores those backups automatically.

Manual rollback:

```bash
wsl-plus rollback
```

Purge WSL Plus user files rather than restoring the previous transaction:

```bash
wsl-plus rollback --purge
```

WSL Plus does not create or enforce a machine lock. A lock written by an
older build is retained byte-for-byte and reported as deprecated state. Remove
one only with the explicit rollback option:

```bash
wsl-plus rollback --purge --remove-machine-lock
```

APT packages and external utilities are never removed automatically because they may be used by other tools.
