# Writing an integration

An integration answers one question: **what already-existing behavior on this
machine must WSL Plus not change?**

It is not a feature switch. An integration can only narrow what a policy
permits; it can never widen it. If you want to *enable* something, that belongs
in `policies/` and `defaults/`, not here.

Two integrations ship:

- `plain-wsl` — publishes no contract. Nothing is treated as owner-protected.
- `example-site` — a complete, working, contract-backed integration whose
  targets are fictional. It detects nothing on a real machine and exists to be
  copied.

## When you need one

You need a contract-backed integration when some other system already owns
files or command names inside the distro, and a convenience layer could
plausibly shadow them. Typical owners: a managed-settings file, a broker
binary, an authorization lane artifact, a pinned tool on `PATH`.

You do not need one to run WSL Plus on a locked-down distro. `restricted +
plain-wsl` is a valid, fully supported selection.

## Layout

```text
integrations/<id>/
  integration.conf
  protected-commands.txt          deprecated compatibility view
  protected-paths.txt             deprecated compatibility view
  contracts/v1/
    contract.conf
    effects.tsv
    detection-facts.tsv
    SHA256SUMS
```

The contract directory must contain **exactly** those four files. An extra
entry, a symlink, or a missing file is a hard failure — the loader compares the
sorted directory listing against the expected set before reading anything.

## `integration.conf`

```ini
INTEGRATION_ID=example-site
REQUIRED_POLICY=restricted
PROTECTED_PATHS_FILE=
PROTECTED_COMMANDS_FILE=
CONTRACT_DIR=contracts/v1
CONTRACT_SCHEMA_VERSION=1
CONTRACT_OWNER_COMMIT=583724ead1e509c359e6d619014817bbba3f4853
CONTRACT_PUBLICATION_COMMIT=b5c59038557394f939dfd1c114e7f8ca377461cd
```

All eight keys are required and no others are permitted. `INTEGRATION_ID` must
match the directory name. `REQUIRED_POLICY`, when set, refuses the integration
under any other policy.

Leave `PROTECTED_PATHS_FILE` and `PROTECTED_COMMANDS_FILE` empty when you
publish a contract — runtime checks materialize exact targets from
`effects.tsv` instead, and the two text files remain only as a human-readable
view. An integration with no contract sets `CONTRACT_DIR=` and uses those files
directly.

### The two commit pins

`CONTRACT_OWNER_COMMIT` must equal the contract's own `OWNER_COMMIT`. It is the
commit in the *owning* project that the contract was audited against.

`CONTRACT_PUBLICATION_COMMIT` is separate and deliberately not compared to
anything: it records which commit published this copy of the contract into WSL
Plus. Both must be lowercase 40-character object IDs.

Two pins, because "what was audited" and "what was shipped" are different
facts, and conflating them hides a stale copy.

## `contract.conf`

```ini
SCHEMA_VERSION=1
CONTRACT_ID=example-site-protected-effects
OWNER_REPOSITORY=example-org/example-site
OWNER_COMMIT=583724ead1e509c359e6d619014817bbba3f4853
POLICY_COMMIT=d402fb69875c882f7062222729750086fc23ba1d
EFFECTS_FILE=effects.tsv
EFFECTS_SHA256=<sha256 of effects.tsv>
DETECTION_FACTS_FILE=detection-facts.tsv
DETECTION_FACTS_SHA256=<sha256 of detection-facts.tsv>
```

`CONTRACT_ID` is owned by whoever publishes the contract. WSL Plus requires
only a well-formed lowercase kebab-case identifier and never matches it against
a hardcoded list. Schema 1 requires the data filenames to be exactly
`effects.tsv` and `detection-facts.tsv`.

## `effects.tsv`

Tab-separated. Two fields per line. Blank lines are ignored.

| Verb | Target | Meaning |
| --- | --- | --- |
| `FILE_NO_WRITE` | absolute path | WSL Plus must not write this file |
| `AUTHORIZATION_LANE_NO_CHANGE` | absolute path | An authorization artifact whose content must not change |
| `COMMAND_RESOLUTION_NO_CHANGE` | command name | This name must resolve to the same binary before and after |

Paths must be normalized and absolute: no `//`, no `/./`, no `/../`, and not
bare `/`. Command names match `[a-zA-Z0-9._+-]+`.

```tsv
FILE_NO_WRITE	/etc/example-site/agent-settings.json
AUTHORIZATION_LANE_NO_CHANGE	/etc/example-site/agent-lanes.json
COMMAND_RESOLUTION_NO_CHANGE	example-agent
```

The installer refuses to proceed if any path it plans to write falls within a
declared protected path, and it compares protected files and command resolution
before and after installation. A change WSL Plus caused fails the transaction
and restores the backup.

## `detection-facts.tsv`

The same tab-separated shape, answering a different question: **is this site
actually deployed on this machine?**

| Fact | Target | Satisfied when |
| --- | --- | --- |
| `ROOT_REGULAR_FILE` | absolute path | the path is a regular file |
| `ROOT_EXECUTABLE` | absolute path | the path is a regular file and executable |

Detection has three states, and the middle one is the point:

- **present** — every fact matched. Selecting a *different* integration is
  refused; you are on a governed machine and asked for the wrong profile.
- **partial** — some matched, some did not. Ambiguous, and refused before any
  mutation. A half-deployed site is not something to guess about.
- **absent** — nothing matched. Any selection is fine.

Detection runs against every integration you did not select, both at install
and in `doctor`. Pick facts that are cheap to stat, root-owned, and genuinely
distinctive.

## `SHA256SUMS`

Exactly three lines, covering `contract.conf`, `effects.tsv`, and
`detection-facts.tsv`. Any other count is rejected. The hashes in
`contract.conf` are checked as well, so a tampered data file fails twice.

## Build one

Copy the example and regenerate the hashes:

```bash
cp -a integrations/example-site integrations/my-site
cd integrations/my-site
$EDITOR contracts/v1/effects.tsv contracts/v1/detection-facts.tsv
```

Then rewrite the metadata and manifest from the files themselves:

```bash
eff=$(sha256sum contracts/v1/effects.tsv | cut -d' ' -f1)
facts=$(sha256sum contracts/v1/detection-facts.tsv | cut -d' ' -f1)
sed -i "s/^EFFECTS_SHA256=.*/EFFECTS_SHA256=$eff/;s/^DETECTION_FACTS_SHA256=.*/DETECTION_FACTS_SHA256=$facts/" contracts/v1/contract.conf
conf=$(sha256sum contracts/v1/contract.conf | cut -d' ' -f1)
printf '%s  contract.conf\n%s  effects.tsv\n%s  detection-facts.tsv\n' "$conf" "$eff" "$facts" > contracts/v1/SHA256SUMS
```

Set `INTEGRATION_ID`, `CONTRACT_ID`, `OWNER_REPOSITORY`, and the commit pins to
real values, then verify:

```bash
./install.sh --policy restricted --integration my-site --check
```

## File modes

The installed contract directory must be `0755` and each of the four files
`0644`, all owned by the installing user, with no symlinks anywhere. `doctor`
checks this on every run. The installer normalizes modes for any
`integrations/*/contracts` directory it stages, so a contract cannot arrive with
surprising permissions.

## Testing

`tests/run.sh` exercises the contract loader against synthetic mutations: a
missing file, an extra entry, a symlinked entry, a tampered hash, an
unsupported schema version, an unreadable file, and a stale pin. If you add a
verb or a fact type, add its rejection case there too.

Every change to `policies/`, `defaults/`, or `integrations/` needs installer,
doctor, migration, and capability-independence coverage.
