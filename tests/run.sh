#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

TEST_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
pass_count=0

pass() {
  printf '[TEST PASS] %s\n' "$1"
  pass_count=$((pass_count + 1))
}

fail() {
  printf '[TEST FAIL] %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f $1 ]] || fail "Expected file: $1"
}

assert_absent() {
  [[ ! -e $1 ]] || fail "Expected path to be absent: $1"
}

assert_eq() {
  [[ $1 == "$2" ]] || fail "Expected '$1' to equal '$2'"
}

new_environment() {
  local root="$TEMP_ROOT/$1"
  mkdir -p "$root/home" "$root/root/etc" "$root/root/proc/self"
  printf '# original bashrc\n' > "$root/home/.bashrc"
  printf '# original tmux\n' > "$root/home/.tmux.conf"
  : > "$root/root/proc/self/mountinfo"
  printf '%s' "$root"
}

run_installer() {
  local root=$1
  shift
  HOME="$root/home" PATH="${WSL_PLUS_TEST_PATH:-$TEST_PATH}" WSL_PLUS_ALLOW_NON_WSL=1 WSL_PLUS_ETC_ROOT="$root/root" "$ROOT_DIR/install.sh" "$@"
}

run_installed() {
  local root=$1
  shift
  HOME="$root/home" PATH="${WSL_PLUS_TEST_PATH:-$TEST_PATH}" WSL_PLUS_ALLOW_NON_WSL=1 WSL_PLUS_ETC_ROOT="$root/root" "$root/home/.local/share/wsl-plus/current/bin/wsl-plus" "$@"
}

create_example_site_facts() {
  local root=$1 scope=${2:-all}
  mkdir -p "$root/root/etc/example-site"
  printf '{}\n' > "$root/root/etc/example-site/agent-settings.json"
  [[ $scope == all ]] || return 0
  mkdir -p "$root/root/etc/example-site" "$root/root/var/lib/example-site" "$root/root/opt/example-site/bin" "$root/root/usr/local/bin"
  printf '{}\n' > "$root/root/etc/example-site/attest.json"
  printf '{}\n' > "$root/root/etc/example-site/agent-lanes.json"
  printf '{}\n' > "$root/root/var/lib/example-site/config-overlay.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/root/opt/example-site/bin/example-agent"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/root/usr/local/bin/example-attest"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$root/root/usr/local/bin/example-attest-admin"
  chmod 000 "$root/root/var/lib/example-site/config-overlay.json"
  chmod 0755 "$root/root/opt/example-site/bin/example-agent" "$root/root/usr/local/bin/example-attest" "$root/root/usr/local/bin/example-attest-admin"
}

expected_version=$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")

# The existing CI entry point invokes this suite, so keep shipped extensionless
# scripts and ble.sh configuration in the same syntax/lint contract even when
# the GitHub credential used to publish a release cannot update workflow YAML.
mapfile -d '' shipped_shell_files < <(
  git -C "$ROOT_DIR" ls-files -z -- \
    '*.sh' '*.bash' 'bin/wsl-plus*' 'core/bash/blesh.rc'
)
for shell_file in "${shipped_shell_files[@]}"; do
  [[ -n $shell_file ]] || continue
  bash -n "$ROOT_DIR/$shell_file"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "${shipped_shell_files[@]/#/$ROOT_DIR/}"
fi
pass 'all tracked shipped shell entry points parse and ShellCheck when available'

# --check is optional and makes no user, root, or package mutation.
check_root=$(new_environment check-only)
mock_check_bin="$check_root/mock-bin"
mkdir -p "$mock_check_bin"
# shellcheck disable=SC2016 # Written literally into the fake executable.
printf '#!/usr/bin/env bash\nprintf invoked >> "$MOCK_APT_LOG"\n' > "$mock_check_bin/apt-get"
chmod 0755 "$mock_check_bin/apt-get"
MOCK_APT_LOG="$check_root/apt.log" WSL_PLUS_TEST_PATH="$mock_check_bin:$TEST_PATH" run_installer "$check_root" --policy home --integration plain-wsl --mode managed --check >/dev/null
assert_absent "$check_root/apt.log"
assert_absent "$check_root/home/.config"
assert_absent "$check_root/home/.local"
assert_eq "$(sed -n '1p' "$check_root/home/.bashrc")" '# original bashrc'
assert_eq "$(sed -n '1p' "$check_root/home/.tmux.conf")" '# original tmux'
pass '--check is optional and zero-mutation'

# Home uses schema 2, bounded blocks, local sessions, and the absolute wrapper.
home_root=$(new_environment home)
run_installer "$home_root" --policy home --integration plain-wsl --mode managed --skip-packages >/dev/null
run_installer "$home_root" --policy home --integration plain-wsl --mode managed --skip-packages >/dev/null
runtime="$home_root/home/.config/wsl-plus/runtime.conf"
assert_file "$runtime"
assert_file "$home_root/home/.local/bin/wsl-plus"
assert_file "$home_root/home/.local/share/wsl-plus/current/bin/wsl-plus-session"
assert_eq "$(grep -Fxc '# >>> wsl-plus managed block >>>' "$home_root/home/.bashrc")" '1'
assert_eq "$(grep -Fxc '# >>> wsl-plus tmux block >>>' "$home_root/home/.tmux.conf")" '1'
assert_eq "$(grep -c 'core/tmux/local-sessions.conf' "$home_root/home/.tmux.conf")" '1'
assert_eq "$(grep -c 'core/tmux/home-sessions.conf' "$home_root/home/.tmux.conf")" '1'
grep -q '^WSL_PLUS_SCHEMA_VERSION=2$' "$runtime" || fail 'Home runtime did not use schema 2'
grep -q '^WSL_PLUS_ENABLE_LOCAL_SESSIONS=1$' "$runtime" || fail 'Home local sessions are not enabled'
grep -q '^WSL_PLUS_SESSION_BACKEND=auto$' "$runtime" || fail 'Home did not select the auto session backend'
grep -q '^WSL_PLUS_ENABLE_BLESH=1$' "$runtime" || fail 'Home should enable ble.sh integration'
run_installed "$home_root" doctor >/dev/null
pass 'home install is idempotent and doctor passes'

# ble.sh uses only WSL Plus's package-owned rc file.
mkdir -p "$home_root/home/.local/share/blesh"
cat > "$home_root/home/.local/share/blesh/ble.sh" <<'EOF_BLESH'
BLE_VERSION=test
bleopt() {
  case $1 in
    complete_auto_complete=1) WSL_PLUS_TEST_BLE_AUTO=1 ;;
    complete_auto_complete_opts) return 0 ;;
    complete_auto_complete_opts-=history-disabled) WSL_PLUS_TEST_BLE_HISTORY=1 ;;
  esac
}
ble-face() {
  case $* in
    '-s auto_complete fg=252,bg=238') WSL_PLUS_TEST_BLE_GHOST_FACE=1 ;;
    '-s syntax_error fg=250') WSL_PLUS_TEST_BLE_ERROR_FACE=1 ;;
  esac
}
ble-attach() { WSL_PLUS_TEST_BLE_ATTACHED=1; }
while (($#)); do
  case $1 in
    --rcfile) . "$2"; shift 2 ;;
    *) shift ;;
  esac
done
EOF_BLESH
command -v script >/dev/null 2>&1 || fail 'script is required for the ble.sh test'
blesh_output=$(HOME="$home_root/home" script -qec "bash --noprofile --norc -ic '. \"$home_root/home/.config/wsl-plus/init.bash\"; printf \"BLE_TEST=%s:%s:%s:%s:%s\\n\" \"\$WSL_PLUS_TEST_BLE_ATTACHED\" \"\$WSL_PLUS_TEST_BLE_AUTO\" \"\$WSL_PLUS_TEST_BLE_HISTORY\" \"\$WSL_PLUS_TEST_BLE_GHOST_FACE\" \"\$WSL_PLUS_TEST_BLE_ERROR_FACE\"'" /dev/null)
printf '%s\n' "$blesh_output" | tr -d '\r' | grep -q '^BLE_TEST=1:1:1:1:1$' || fail 'ble.sh suggestions and package-owned faces did not attach'
pass 'detected ble.sh uses modern suggestions and package-owned faces'

# Older ble.sh releases expose complete_auto_history instead of the modern
# complete_auto_complete_opts history source selector.
cat > "$home_root/home/.local/share/blesh/ble.sh" <<'EOF_LEGACY_BLESH'
BLE_VERSION=test-legacy
bleopt() {
  case $1 in
    complete_auto_complete_opts) return 1 ;;
    complete_auto_complete_opts*) WSL_PLUS_TEST_BLE_UNKNOWN=1; return 1 ;;
    complete_auto_history=1) WSL_PLUS_TEST_BLE_LEGACY_HISTORY=1 ;;
  esac
}
ble-face() { :; }
ble-attach() { :; }
while (($#)); do
  case $1 in
    --rcfile) . "$2"; shift 2 ;;
    *) shift ;;
  esac
done
EOF_LEGACY_BLESH
blesh_output=$(HOME="$home_root/home" script -qec "bash --noprofile --norc -ic '. \"$home_root/home/.config/wsl-plus/init.bash\"; printf \"BLE_LEGACY_TEST=%s:%s\\n\" \"\${WSL_PLUS_TEST_BLE_LEGACY_HISTORY-}\" \"\${WSL_PLUS_TEST_BLE_UNKNOWN-}\"'" /dev/null)
printf '%s\n' "$blesh_output" | tr -d '\r' | grep -q '^BLE_LEGACY_TEST=1:$' || fail 'older ble.sh did not receive the legacy history suggestion setting'
pass 'detected older ble.sh uses its supported history suggestion setting'

session_status=$(run_installed "$home_root" session status)
printf '%s\n' "$session_status" | grep -q '^Local sessions: enabled$' || fail 'Home local session status failed'
printf '%s\n' "$session_status" | grep -q '^Selected backend: auto$' || fail 'Home backend is not auto'
run_installed "$home_root" session list >/dev/null
assert_eq "$(run_installed "$home_root" ssh-agent status)" 'Windows SSH-agent adapter: not configured'
grep -q "@resurrect-processes 'false'" "$home_root/home/.local/share/wsl-plus/current/core/tmux/home-sessions.conf" || fail 'Process restoration is not disabled'
pass 'Home optional adapters remain bounded'

fake_relay="$home_root/home/npiperelay.exe"
printf '#!/usr/bin/env bash\nexit 1\n' > "$fake_relay"
chmod 0755 "$fake_relay"
if run_installed "$home_root" ssh-agent configure --relay relative/npiperelay.exe >/dev/null 2>&1; then fail 'SSH relay accepted a relative path'; fi
if run_installed "$home_root" ssh-agent configure --relay "$fake_relay" >/dev/null 2>&1; then fail 'SSH relay accepted a non-Windows path'; fi
pass 'SSH-agent adapter requires explicit relay configuration'

if run_installer "$home_root" --policy home --integration example-site --mode managed --skip-packages >/dev/null 2>&1; then fail 'home + example-site should be rejected'; fi
pass 'integration selection cannot widen policy capabilities'

# The restricted profile installs directly with native-only local sessions and no root lock.
restricted_root=$(new_environment restricted)
run_installer "$restricted_root" --policy restricted --integration example-site --mode augment --skip-packages >/dev/null
assert_absent "$restricted_root/root/etc/wsl-plus/machine-policy.conf"
assert_file "$restricted_root/home/.local/bin/wsl-plus"
restricted_runtime="$restricted_root/home/.config/wsl-plus/runtime.conf"
grep -q '^WSL_PLUS_ENABLE_LOCAL_SESSIONS=1$' "$restricted_runtime" || fail 'Restricted local sessions are disabled'
grep -q '^WSL_PLUS_SESSION_BACKEND=native$' "$restricted_runtime" || fail 'Restricted backend is not native'
grep -q 'core/tmux/local-sessions.conf' "$restricted_root/home/.tmux.conf" || fail 'Restricted local tmux config is absent'
if grep -q 'core/tmux/home-sessions.conf' "$restricted_root/home/.tmux.conf"; then fail 'Restricted sourced external Home adapters'; fi
restricted_status=$(run_installed "$restricted_root" session status)
printf '%s\n' "$restricted_status" | grep -q '^Selected backend: native$' || fail 'Restricted status is not native'
fake_resurrect="$restricted_root/fake-resurrect"
mkdir -p "$fake_resurrect/scripts"
# The generated fixture expands this variable when invoked.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nprintf invoked >> "$FAKE_RESURRECT_LOG"\n' > "$fake_resurrect/scripts/save.sh"
cp "$fake_resurrect/scripts/save.sh" "$fake_resurrect/scripts/restore.sh"
chmod 0755 "$fake_resurrect/scripts/save.sh" "$fake_resurrect/scripts/restore.sh"
if FAKE_RESURRECT_LOG="$restricted_root/resurrect.log" WSL_PLUS_RESURRECT_ROOT="$fake_resurrect" run_installed "$restricted_root" session save >/dev/null 2>&1; then fail 'Native backend allowed save'; fi
if FAKE_RESURRECT_LOG="$restricted_root/resurrect.log" WSL_PLUS_RESURRECT_ROOT="$fake_resurrect" run_installed "$restricted_root" session restore >/dev/null 2>&1; then fail 'Native backend allowed restore'; fi
assert_absent "$restricted_root/resurrect.log"
if run_installed "$restricted_root" ssh-agent status >/dev/null 2>&1; then fail 'Restricted allowed Windows SSH agent'; fi
run_installed "$restricted_root" doctor >/dev/null
pass 'Restricted direct install preserves real boundaries and enables local sessions'

chmod 0600 "$restricted_root/home/.local/share/wsl-plus/current/integrations/example-site/contracts/v1/effects.tsv"
if run_installed "$restricted_root" doctor >/dev/null 2>&1; then fail 'Doctor accepted an invalid installed contract mode'; fi
chmod 0644 "$restricted_root/home/.local/share/wsl-plus/current/integrations/example-site/contracts/v1/effects.tsv"
run_installed "$restricted_root" doctor >/dev/null
pass 'doctor enforces installed contract ownership and modes'

# Native list/pick/attach/create never invokes Sesh or tmux-resurrect.
session_bin="$restricted_root/session-bin"
session_log="$restricted_root/session.log"
mkdir -p "$session_bin" "$restricted_root/project"
cat > "$session_bin/tmux" <<'EOF_TMUX'
#!/usr/bin/env bash
printf 'tmux:%s\n' "$*" >> "$FAKE_SESSION_LOG"
case $1 in
  has-session) [[ ${FAKE_TMUX_HAS:-0} == 1 ]] ;;
  list-sessions) printf 'tmux\tdemo\t%s\n' "$FAKE_SESSION_DIR" ;;
  *) exit 0 ;;
esac
EOF_TMUX
cat > "$session_bin/fzf" <<'EOF_FZF'
#!/usr/bin/env bash
head -n 1
EOF_FZF
cat > "$session_bin/sesh" <<'EOF_SESH'
#!/usr/bin/env bash
printf 'sesh:%s\n' "$*" >> "$FAKE_SESSION_LOG"
exit 90
EOF_SESH
chmod 0755 "$session_bin/tmux" "$session_bin/fzf" "$session_bin/sesh"
FAKE_SESSION_LOG="$session_log" FAKE_SESSION_DIR="$restricted_root/project" FAKE_TMUX_HAS=1 WSL_PLUS_TEST_PATH="$session_bin:$TEST_PATH" run_installed "$restricted_root" session attach demo >/dev/null
FAKE_SESSION_LOG="$session_log" FAKE_SESSION_DIR="$restricted_root/project" FAKE_TMUX_HAS=0 WSL_PLUS_TEST_PATH="$session_bin:$TEST_PATH" run_installed "$restricted_root" session create "$restricted_root/project" >/dev/null
FAKE_SESSION_LOG="$session_log" FAKE_SESSION_DIR="$restricted_root/project" FAKE_TMUX_HAS=1 WSL_PLUS_TEST_PATH="$session_bin:$TEST_PATH" run_installed "$restricted_root" session pick >/dev/null
grep -q '^tmux:attach-session -t =demo$' "$session_log" || fail 'Native attach did not use exact tmux targeting'
grep -q '^tmux:new-session -s project -c ' "$session_log" || fail 'Native create did not create a directory session'
if grep -q '^sesh:' "$session_log"; then fail 'Native backend invoked Sesh'; fi
pass 'native sessions support list/pick/attach/create without external adapters'

# Optional plan input is verified but never mandatory.
plan_root=$(new_environment optional-plan)
check_output=$(run_installer "$plan_root" --policy restricted --integration example-site --mode augment --skip-packages --check)
plan_id=$(printf '%s\n' "$check_output" | awk '/Plan ID:/ {print $3}')
[[ $plan_id =~ ^[0-9a-f]{64}$ ]] || fail 'Check did not emit a SHA-256 plan ID'
if run_installer "$plan_root" --policy restricted --integration example-site --mode augment --skip-packages --apply-plan deadbeef >/dev/null 2>&1; then fail 'Incorrect plan ID was accepted'; fi
printf '# state changed after preview\n' >> "$plan_root/home/.bashrc"
if run_installer "$plan_root" --policy restricted --integration example-site --mode augment --skip-packages --apply-plan "$plan_id" >/dev/null 2>&1; then fail 'Stale plan ID was accepted after shell state changed'; fi
check_output=$(run_installer "$plan_root" --policy restricted --integration example-site --mode augment --skip-packages --check)
plan_id=$(printf '%s\n' "$check_output" | awk '/Plan ID:/ {print $3}')
run_installer "$plan_root" --policy restricted --integration example-site --mode augment --skip-packages --apply-plan "$plan_id" >/dev/null
pass 'optional check/apply verification remains deterministic'

# Legacy lock bytes are preserved and do not gate compatibility changes.
legacy_root=$(new_environment legacy-lock)
mkdir -p "$legacy_root/root/etc/wsl-plus"
cat > "$legacy_root/root/etc/wsl-plus/machine-policy.conf" <<'EOF_LOCK'
SITE=home
POLICY=home
INTEGRATION=plain-wsl
MODE=managed
WSL_PLUS_VERSION=0.4.0
ALLOW_PROFILE_SWITCH=0
EOF_LOCK
legacy_hash_before=$(sha256sum "$legacy_root/root/etc/wsl-plus/machine-policy.conf" | awk '{print $1}')
run_installer "$legacy_root" --policy restricted --integration example-site --mode augment --skip-packages >/dev/null
legacy_hash_after=$(sha256sum "$legacy_root/root/etc/wsl-plus/machine-policy.conf" | awk '{print $1}')
assert_eq "$legacy_hash_after" "$legacy_hash_before"
run_installed "$legacy_root" rollback --purge --remove-machine-lock >/dev/null
assert_absent "$legacy_root/root/etc/wsl-plus/machine-policy.conf"
pass 'legacy machine locks are preserved, ignored, and removed only when explicit'

# Later PATH maintenance passes; WSL Plus-caused PATH mutation fails and rolls back.
# shellcheck disable=SC2016 # Written literally into the future shell file.
printf '\nexport PATH="/tmp/later-approved:$PATH"\n' >> "$restricted_root/home/.bashrc"
run_installed "$restricted_root" doctor >/dev/null
pass 'doctor accepts later PATH maintenance when WSL Plus is not causal'

fail_root=$(new_environment path-drift)
cat > "$fail_root/home/.bashrc" <<'EOF_BASHRC'
# original
if [[ -r "$HOME/.config/wsl-plus/runtime.conf" && ${WSL_PLUS_DISABLE:-0} != 1 ]]; then
  export PATH="/tmp/wsl-plus-forbidden:$PATH"
fi
EOF_BASHRC
if run_installer "$fail_root" --policy restricted --integration example-site --mode augment --skip-packages >/dev/null 2>&1; then fail 'WSL Plus-caused PATH mutation was accepted'; fi
assert_absent "$fail_root/home/.config/wsl-plus"
assert_absent "$fail_root/home/.local/share/wsl-plus/current"
assert_eq "$(grep -Fxc '# >>> wsl-plus managed block >>>' "$fail_root/home/.bashrc" || true)" '0'
pass 'causal shell failure restores the WSL Plus transaction'

# Package-provided Git is captured after the authorized package step.
package_root=$(new_environment package-git)
package_bin="$package_root/package-bin"
mkdir -p "$package_bin"
cat > "$package_bin/apt-get" <<'EOF_APT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_APT_LOG"
if [[ $1 == install ]]; then
  for command_name in git rg jq tmux shellcheck fzf zoxide; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$MOCK_PACKAGE_BIN/$command_name"
    chmod 0755 "$MOCK_PACKAGE_BIN/$command_name"
  done
fi
exit 0
EOF_APT
cat > "$package_bin/apt-cache" <<'EOF_APT_CACHE'
#!/usr/bin/env bash
if [[ $1 == policy ]]; then
  printf '%s:\n' "$2"
  if [[ $2 == tldr ]]; then
    printf '  Candidate: (none)\n'
  elif [[ ${LC_ALL-} == C ]]; then
    printf '  Candidate: test-version\n'
  else
    printf '  Installationskandidat: test-version\n'
  fi
fi
EOF_APT_CACHE
printf '#!/usr/bin/env bash\nexec "$@"\n' > "$package_bin/sudo"
chmod 0755 "$package_bin/apt-get" "$package_bin/apt-cache" "$package_bin/sudo"
MOCK_APT_LOG="$package_root/apt.log" MOCK_PACKAGE_BIN="$package_bin" WSL_PLUS_TEST_PATH="$package_bin:$TEST_PATH" run_installer "$package_root" --policy home --integration plain-wsl --mode managed >/dev/null
assert_file "$package_bin/git"
if grep -qw tldr "$package_root/apt.log"; then fail 'Optional package without an APT candidate was requested'; fi
grep -qw btop "$package_root/apt.log" || fail 'Localized APT candidate probe skipped an available optional package'
pass 'package-provided tools enter the baseline and optional package candidates are locale-independent'

# Contract schema, hashes, pins, and deployment-fact states fail before any
# installation mutation when they are missing, stale, partial, or unsupported.
contract_source="$ROOT_DIR/integrations/example-site/contracts/v1"
contract_copy="$TEMP_ROOT/contract-copy"
cp -a "$contract_source" "$contract_copy"
(
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/config.sh"
  source "$ROOT_DIR/lib/integration-contract.sh"
  # shellcheck disable=SC2034 # Consumed through a contract-helper nameref.
  declare -A TEST_CONTRACT=()
  load_integration_contract "$contract_copy" TEST_CONTRACT
) >/dev/null || fail 'Valid example-site contract did not load'

cp -a "$contract_source" "$TEMP_ROOT/contract-missing"
rm -f "$TEMP_ROOT/contract-missing/effects.tsv"
if (source "$ROOT_DIR/lib/common.sh"; source "$ROOT_DIR/lib/config.sh"; source "$ROOT_DIR/lib/integration-contract.sh"; declare -A C=(); load_integration_contract "$TEMP_ROOT/contract-missing" C) >/dev/null 2>&1; then fail 'Contract with missing data loaded'; fi

cp -a "$contract_source" "$TEMP_ROOT/contract-tampered"
printf '# tampered\n' >> "$TEMP_ROOT/contract-tampered/effects.tsv"
if (source "$ROOT_DIR/lib/common.sh"; source "$ROOT_DIR/lib/config.sh"; source "$ROOT_DIR/lib/integration-contract.sh"; declare -A C=(); load_integration_contract "$TEMP_ROOT/contract-tampered" C) >/dev/null 2>&1; then fail 'Contract with a bad hash loaded'; fi

cp -a "$contract_source" "$TEMP_ROOT/contract-extra"
printf 'unexpected\n' > "$TEMP_ROOT/contract-extra/extra.txt"
if (source "$ROOT_DIR/lib/common.sh"; source "$ROOT_DIR/lib/config.sh"; source "$ROOT_DIR/lib/integration-contract.sh"; declare -A C=(); load_integration_contract "$TEMP_ROOT/contract-extra" C) >/dev/null 2>&1; then fail 'Contract with an unexpected entry loaded'; fi

cp -a "$contract_source" "$TEMP_ROOT/contract-symlink"
rm -f "$TEMP_ROOT/contract-symlink/effects.tsv"
ln -s "$contract_source/effects.tsv" "$TEMP_ROOT/contract-symlink/effects.tsv"
if (source "$ROOT_DIR/lib/common.sh"; source "$ROOT_DIR/lib/config.sh"; source "$ROOT_DIR/lib/integration-contract.sh"; declare -A C=(); load_integration_contract "$TEMP_ROOT/contract-symlink" C) >/dev/null 2>&1; then fail 'Contract with a symlinked data file loaded'; fi

cp -a "$contract_source" "$TEMP_ROOT/contract-unsupported"
sed -i 's/^SCHEMA_VERSION=1$/SCHEMA_VERSION=99/' "$TEMP_ROOT/contract-unsupported/contract.conf"
if (source "$ROOT_DIR/lib/common.sh"; source "$ROOT_DIR/lib/config.sh"; source "$ROOT_DIR/lib/integration-contract.sh"; declare -A C=(); load_integration_contract "$TEMP_ROOT/contract-unsupported" C) >/dev/null 2>&1; then fail 'Unsupported contract schema loaded'; fi

cp -a "$contract_source" "$TEMP_ROOT/contract-unreadable"
chmod 000 "$TEMP_ROOT/contract-unreadable/contract.conf"
if [[ ! -r $TEMP_ROOT/contract-unreadable/contract.conf ]]; then
  if (source "$ROOT_DIR/lib/common.sh"; source "$ROOT_DIR/lib/config.sh"; source "$ROOT_DIR/lib/integration-contract.sh"; declare -A C=(); load_integration_contract "$TEMP_ROOT/contract-unreadable" C) >/dev/null 2>&1; then fail 'Unreadable contract metadata loaded'; fi
fi
chmod 0644 "$TEMP_ROOT/contract-unreadable/contract.conf"

if (
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/config.sh"
  source "$ROOT_DIR/lib/integration-contract.sh"
  # shellcheck disable=SC2034 # Both arrays are consumed through helper namerefs.
  declare -A I=() C=()
  load_kv_config "$ROOT_DIR/integrations/example-site/integration.conf" I
  load_integration_contract "$contract_source" C
  # shellcheck disable=SC2034 # Read through validate_integration_contract_pin.
  I[CONTRACT_OWNER_COMMIT]=0000000000000000000000000000000000000000
  validate_integration_contract_pin I C
) >/dev/null 2>&1; then fail 'Stale contract owner pin was accepted'; fi
if (
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/config.sh"
  source "$ROOT_DIR/lib/integration-contract.sh"
  # shellcheck disable=SC2034 # Both arrays are consumed through helper namerefs.
  declare -A I=() C=()
  load_kv_config "$ROOT_DIR/integrations/example-site/integration.conf" I
  load_integration_contract "$contract_source" C
  # shellcheck disable=SC2034 # Read through validate_integration_contract_pin.
  I[CONTRACT_PUBLICATION_COMMIT]=not-a-commit
  validate_integration_contract_pin I C
) >/dev/null 2>&1; then fail 'Malformed contract publication pin was accepted'; fi
pass 'Integration contracts reject missing, extra, symlinked, tampered, unsupported, unreadable, and stale inputs'

partial_root=$(new_environment partial-example-site)
create_example_site_facts "$partial_root" partial
if run_installer "$partial_root" --policy home --integration plain-wsl --mode managed --skip-packages >/dev/null 2>&1; then fail 'Partial example-site facts were accepted'; fi
assert_absent "$partial_root/home/.config"

fact_root=$(new_environment example-site-facts)
run_installer "$fact_root" --policy restricted --integration plain-wsl --mode augment --skip-packages >/dev/null
create_example_site_facts "$fact_root" all
if run_installer "$fact_root" --policy restricted --integration plain-wsl --mode augment --skip-packages >/dev/null 2>&1; then fail 'Complete example-site facts allowed plain-wsl'; fi
run_installer "$fact_root" --policy restricted --integration example-site --mode augment --skip-packages >/dev/null
run_installed "$fact_root" doctor >/dev/null
assert_absent "$fact_root/root/etc/wsl-plus/machine-policy.conf"
pass 'Detection facts reject ambiguity and allow a lock-free plain-wsl-to-example-site upgrade'

# All declared Windows mount/executable boundaries are detected read-only.
system_mount_root=$(new_environment system-mount-boundary)
cat > "$system_mount_root/root/proc/self/mountinfo" <<'EOF_SYSTEM_MOUNTS'
74 78 0:31 / /mnt/wsl rw,relatime shared:1 - tmpfs none rw
79 78 0:37 / /mnt/wslg rw,relatime shared:2 - tmpfs none rw
EOF_SYSTEM_MOUNTS
run_installer "$system_mount_root" --policy restricted --integration plain-wsl --mode augment --skip-packages >/dev/null

mount_root=$(new_environment mount-boundary)
printf '1 0 0:1 / /mnt/d rw - drvfs D: rw\n' > "$mount_root/root/proc/self/mountinfo"
if run_installer "$mount_root" --policy restricted --integration plain-wsl --mode augment --skip-packages >/dev/null 2>&1; then fail 'Restricted accepted a Windows drive mount'; fi
for windows_command in powershell.exe cmd.exe explorer.exe wscript.exe cscript.exe; do
  command_root=$(new_environment "interop-${windows_command%.*}")
  command_bin="$command_root/windows-bin"
  mkdir -p "$command_bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$command_bin/$windows_command"
  chmod 0755 "$command_bin/$windows_command"
  if WSL_PLUS_TEST_PATH="$command_bin:$TEST_PATH" run_installer "$command_root" --policy restricted --integration plain-wsl --mode augment --skip-packages >/dev/null 2>&1; then fail "Restricted accepted $windows_command"; fi
done
pass 'Windows-backed mounts are denied without rejecting WSL system mounts, and all declared Windows executables are detected'

# A synthetic third profile proves session and SSH behavior use capabilities.
third_root=$(new_environment third-profile)
mkdir -p "$third_root/home/.config/wsl-plus"
cat > "$third_root/home/.config/wsl-plus/runtime.conf" <<EOF_THIRD
WSL_PLUS_SCHEMA_VERSION=2
WSL_PLUS_VERSION=$expected_version
WSL_PLUS_POLICY=third-profile
WSL_PLUS_INTEGRATION=plain-wsl
WSL_PLUS_MODE=augment
WSL_PLUS_ALLOW_WINDOWS_INTEROP=1
WSL_PLUS_ALLOW_WINDOWS_AUTOMOUNT=1
WSL_PLUS_ALLOW_CROSS_FILESYSTEM=1
WSL_PLUS_ALLOW_WINDOWS_CLIPBOARD=1
WSL_PLUS_ALLOW_WINDOWS_APP_LAUNCH=1
WSL_PLUS_ALLOW_GIT_CREDENTIAL_BRIDGE=1
WSL_PLUS_ALLOW_SHARED_SSH_AGENT=1
WSL_PLUS_ALLOW_CLOUD_HISTORY_SYNC=0
WSL_PLUS_ALLOW_WINDOWS_PATH_IMPORT=1
WSL_PLUS_IMPORT_WINDOWS_PATH=0
WSL_PLUS_ENABLE_FZF=1
WSL_PLUS_ENABLE_BLESH=1
WSL_PLUS_ENABLE_ZOXIDE=1
WSL_PLUS_ENABLE_NAVIGATION_HELPERS=1
WSL_PLUS_ENABLE_HISTORY_SETTINGS=1
WSL_PLUS_ENABLE_HISTORY_PROMPT_HOOK=1
WSL_PLUS_ENABLE_LOCAL_SESSIONS=1
WSL_PLUS_SESSION_BACKEND=native
WSL_PLUS_MANAGE_PROMPT=0
WSL_PLUS_MANAGE_TMUX=1
WSL_PLUS_PACKAGES_SKIPPED=1
EOF_THIRD
third_runtime="$third_root/home/.config/wsl-plus/runtime.conf"
third_session=$(HOME="$third_root/home" WSL_PLUS_ROOT="$ROOT_DIR" WSL_PLUS_RUNTIME="$third_runtime" PATH="$TEST_PATH" "$ROOT_DIR/bin/wsl-plus-session" status)
printf '%s\n' "$third_session" | grep -q '^Selected backend: native$' || fail 'Third profile sessions failed'
third_ssh=$(HOME="$third_root/home" WSL_PLUS_ROOT="$ROOT_DIR" WSL_PLUS_RUNTIME="$third_runtime" PATH="$TEST_PATH" "$ROOT_DIR/bin/wsl-plus-ssh-agent" status)
assert_eq "$third_ssh" 'Windows SSH-agent adapter: not configured'
pass 'synthetic profile behavior depends on capabilities, not identity'

# Schema 1 maps only legacy Home sessions.
cat > "$third_runtime" <<'EOF_LEGACY'
WSL_PLUS_VERSION=0.4.0
WSL_PLUS_POLICY=restricted
WSL_PLUS_ENABLE_HOME_SESSIONS=1
EOF_LEGACY
if HOME="$third_root/home" WSL_PLUS_ROOT="$ROOT_DIR" WSL_PLUS_RUNTIME="$third_runtime" PATH="$TEST_PATH" "$ROOT_DIR/bin/wsl-plus-session" status >/dev/null 2>&1; then fail 'Schema 1 restricted policy enabled Home sessions'; fi
sed -i 's/WSL_PLUS_POLICY=restricted/WSL_PLUS_POLICY=home/' "$third_runtime"
HOME="$third_root/home" WSL_PLUS_ROOT="$ROOT_DIR" WSL_PLUS_RUNTIME="$third_runtime" PATH="$TEST_PATH" "$ROOT_DIR/bin/wsl-plus-session" status >/dev/null
pass 'schema 1 migration preserves old Home and restricted behavior'

run_installed "$home_root" rollback --purge >/dev/null
assert_absent "$home_root/home/.config/wsl-plus"
assert_absent "$home_root/home/.local/share/wsl-plus/current"
assert_absent "$home_root/home/.local/bin/wsl-plus"
pass 'purge removes user-level WSL Plus state'

marker_root=$(new_environment malformed-marker)
printf '%s\n' '# >>> wsl-plus managed block >>>' >> "$marker_root/home/.bashrc"
if run_installer "$marker_root" --policy home --integration plain-wsl --mode managed --skip-packages >/dev/null 2>&1; then fail 'Malformed marker block was accepted'; fi
assert_absent "$marker_root/home/.config/wsl-plus"
pass 'malformed managed markers fail closed'

python3 - <<'PY'
from pathlib import Path

text = Path("core/session/sesh.toml").read_text(encoding="utf-8")
try:
    import tomllib
except ModuleNotFoundError:
    if any(line.strip() and not line.lstrip().startswith("#") for line in text.splitlines()):
        raise SystemExit("tomllib is required once sesh.toml contains data")
else:
    tomllib.loads(text)
PY
pass 'safe Sesh configuration parses as TOML'

printf '\n%d tests passed.\n' "$pass_count"
