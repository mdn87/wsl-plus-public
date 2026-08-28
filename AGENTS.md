# WSL Plus agent guidance

WSL Plus is a policy-aware quality-of-life layer for WSL. Interpret authority
in this order: an identified site or corporate source, an explicit owner
decision, a measured integration invariant, then a WSL Plus product default.

A product default is not a policy prohibition. Fail closed only at an
enumerated capability or a measured protected effect; neutral local Linux
behavior stays available unless an authority above explicitly restricts it.

Keep these boundaries intact:

1. `core/` contains neutral shell and terminal behavior. It must not decide
   whether Windows interop, cross-filesystem access, credential bridges, or
   agent tooling are permitted.
2. `policies/` expresses site capabilities; `defaults/` selects product
   behavior for each shipped profile. A policy file contains capability keys
   only.
3. `integrations/` protects environment-specific effects. An integration may
   narrow a capability. It may never widen one, and it may never freeze
   unrelated machine maintenance.
4. The `restricted` capability set is fail-closed for Windows mounts, Windows
   executables, cross-filesystem access, and credential bridges. Do not infer
   additional denials from the profile name — read the capability keys.
5. A published contract is additive-only. WSL Plus must not change the exact
   protected files, command-resolution effects, or authorization-lane facts a
   versioned owner contract declares.
6. Home orchestration adapters stay disabled under `restricted`. That profile
   may use bounded native tmux list, pick, attach, and create; it must not
   invoke Sesh or tmux-resurrect, restore processes, launch project commands or
   agents, clone or mutate repositories, or create or manage worktrees.
7. External utilities are optional adapters. Do not download them during normal
   installation, source their arbitrary user startup configuration, or give
   them ownership of shell startup, credentials, repositories, MCP
   configuration, or agent lifecycle.
8. Never make `/etc/wsl.conf` an implicit installer side effect. Any future
   host-configuration command must be explicit, policy-gated, separately
   reviewed, and rollback-capable.
9. Do not introduce repository synchronization or multi-writer Git behavior.
   Cross-filesystem access is not permission for Windows Git, WSL Git, a sync
   daemon, or an agent to mutate the same checkout concurrently.
10. Managed shell changes must stay marker-bounded, idempotent, backed up, and
    removable. The package never replaces `.bashrc` or `.tmux.conf`.
11. Configuration files are parsed with the restricted key/value reader. Never
    source a configuration file as shell code.
12. Add or update tests for every policy, installer, integration, or session
    change. Run `tests/run.sh` and ShellCheck before publishing.

The test suite needs `bash`, `git`, and util-linux `script`; it will not run on
Git Bash for Windows, which has no `script` binary. Run it inside WSL or on
Linux.
