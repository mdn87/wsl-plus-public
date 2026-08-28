# Policy model

WSL Plus separates authority from product choice. That separation prevents a
conservative compatibility setting from becoming an invented site-policy
prohibition.

## Authority order

1. An identified corporate source controls corporate requirements.
2. An explicit owner decision controls local operating choices.
3. A measured integration invariant protects an effect owned by another
   system.
4. A WSL Plus product default selects ordinary shell and terminal behavior.

Fail closed only when an enumerated capability or a measured protected effect
requires it. A product default is not a corporate or source-policy gate.

## Configuration ownership

| Surface | Category | What it decides |
| --- | --- | --- |
| `policies/<id>.conf` | Site capability | Whether Windows interop, Windows mounts, cross-filesystem access, clipboard/app launch, credential bridges, shared SSH agent, cloud history, and Windows PATH import are permitted |
| `defaults/<id>.conf` | Product default | Mode/integration selection, fzf, ble.sh, zoxide, navigation/history behavior, local sessions, session backend, prompt management, and tmux management |
| `integrations/<id>/` | Integration invariant | Exact owner-published files, command-resolution effects, authorization-lane effects, and deployment detection facts WSL Plus must preserve |
| `runtime.conf` | Selected runtime | The capability and default values chosen during installation; schema 2 records both explicitly |

For version 0.5.x, readers also accept the schema-1 Home session field from
0.4.x. That compatibility reader maps it only for the old Home profile and is
scheduled for removal in 0.6.0; reinstalling writes schema 2.

Runtime code gates effects on capability values. Policy IDs select shipped
configuration files; they do not act as hidden behavior switches.

## Shipped profiles

### Home

Home permits Windows interop, automounted drives, cross-filesystem helpers,
clipboard/application launching, and an explicitly configured Windows
SSH-agent relay. These permissions do not force a bridge to be configured.

Home defaults enable local shell QoL and use the `auto` session backend. That
backend may use an already installed Sesh or tmux-resurrect adapter with the
bounded WSL Plus configuration. Process restoration remains disabled.

### Restricted

`restricted` denies Windows interop, direct Windows drive mounts,
cross-filesystem access, clipboard/application bridges, credential bridges,
shared SSH agents, cloud history, and Windows PATH import. It is the profile
for a distro that a separate system already governs.

Its product defaults preserve the existing prompt and enable local history,
fzf, ble.sh, zoxide, and bounded native tmux sessions. Native sessions may
list, pick, attach, or create a tmux session at an existing directory. They do
not invoke Sesh or tmux-resurrect, restore processes, launch project commands
or agents, clone or mutate repositories, or create/manage worktrees.

## Integrations

`plain-wsl` keeps a small command-resolution smoke set. It publishes no
contract, so nothing on the machine is treated as owner-protected.

`example-site` is a complete worked example of a contract-backed integration.
It requires the `restricted` profile and consumes
`integrations/example-site/contracts/v1/`. Its effects and detection facts name
fictional paths under `/etc/example-site/` and `/opt/example-site/`, so it never
detects anything on a real machine, but it exercises the whole contract path and
is the template to copy when writing your own. See
[INTEGRATIONS.md](INTEGRATIONS.md).

For every integration that publishes a contract, WSL Plus validates its schema,
hashes, audited owner baseline, and separate publishing commit pin before
mutation. Detection then runs against every integration you did not select. If
one integration's facts are all present, selecting a different integration is
rejected. A partial fact set is ambiguous and also fails before mutation. When
every fact is absent, an explicit contained `restricted + plain-wsl` install
remains valid.

## Plans and legacy locks

`--check` is an optional zero-mutation preview for every profile. Supplying
`--apply-plan` asks the installer to verify that exact preview; no profile
requires a two-pass install.

WSL Plus does not create or enforce `/etc/wsl-plus/machine-policy.conf`. A
lock written by an older build is preserved and reported as deprecated state.
Only the explicit `rollback --remove-machine-lock` option removes it.

## Extending the model

A new policy must contain capability keys only. A new defaults file may select
product behavior only within those capabilities. A new integration must
publish exact effect-based checks and cannot widen a denied capability.

Every change to `policies/`, `defaults/`, or `integrations/` requires
installer, doctor, migration, and capability-independence tests.
