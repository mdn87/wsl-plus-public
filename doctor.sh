#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/config.sh
. "$ROOT_DIR/lib/config.sh"
# shellcheck source=lib/integration-contract.sh
. "$ROOT_DIR/lib/integration-contract.sh"

doctor_tmp=$(mktemp -d)
trap 'rm -rf -- "$doctor_tmp"' EXIT

failures=0
warnings=0

pass() {
  printf '[PASS] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*"
  warnings=$((warnings + 1))
}

fail() {
  printf '[FAIL] %s\n' "$*"
  failures=$((failures + 1))
}

info() {
  printf '[INFO] %s\n' "$*"
}

check_file_marker() {
  local file=$1 begin=$2 end=$3 label=$4
  local begin_count=0 end_count=0

  if [[ ! -f $file ]]; then
    fail "$label is missing: $file"
    return
  fi

  begin_count=$(grep -Fxc "$begin" "$file" 2>/dev/null || true)
  end_count=$(grep -Fxc "$end" "$file" 2>/dev/null || true)
  if [[ $begin_count == 1 && $end_count == 1 ]]; then
    pass "$label has one bounded managed block"
  else
    fail "$label marker count is begin=$begin_count end=$end_count"
  fi
}

if is_wsl || [[ ${WSL_PLUS_ALLOW_NON_WSL:-0} == 1 ]]; then
  pass 'WSL runtime detected'
else
  fail 'Not running inside WSL'
fi

runtime_file="$HOME/.config/wsl-plus/runtime.conf"
if [[ ! -r $runtime_file ]]; then
  fail "Runtime configuration is missing: $runtime_file"
  printf '\nDoctor finished with %d failure(s) and %d warning(s).\n' "$failures" "$warnings"
  exit 1
fi

declare -A RUNTIME=()
if ! load_kv_config "$runtime_file" RUNTIME; then
  fail 'Runtime configuration is invalid'
  exit 1
fi

schema=${RUNTIME[WSL_PLUS_SCHEMA_VERSION]-1}
if [[ $schema == 1 ]]; then
  required_runtime_keys=(
    WSL_PLUS_VERSION WSL_PLUS_POLICY WSL_PLUS_INTEGRATION WSL_PLUS_MODE
    WSL_PLUS_ALLOW_WINDOWS_INTEROP WSL_PLUS_ALLOW_CROSS_FILESYSTEM
    WSL_PLUS_ALLOW_SHARED_SSH_AGENT
    WSL_PLUS_ENABLE_FZF WSL_PLUS_ENABLE_BLESH WSL_PLUS_ENABLE_ZOXIDE
    WSL_PLUS_ENABLE_HISTORY_SETTINGS WSL_PLUS_ENABLE_HISTORY_PROMPT_HOOK
    WSL_PLUS_ENABLE_HOME_SESSIONS WSL_PLUS_MANAGE_PROMPT
    WSL_PLUS_MANAGE_TMUX WSL_PLUS_PACKAGES_SKIPPED
  )
  if config_require_keys RUNTIME "${required_runtime_keys[@]}"; then
    info 'Runtime schema 1 is supported for one migration release; reinstall to write schema 2.'
  else
    fail 'Legacy runtime configuration is incomplete'
  fi
  RUNTIME[WSL_PLUS_SCHEMA_VERSION]=1
  RUNTIME[WSL_PLUS_ALLOW_WINDOWS_AUTOMOUNT]=${RUNTIME[WSL_PLUS_ALLOW_WINDOWS_AUTOMOUNT]-0}
  RUNTIME[WSL_PLUS_ALLOW_WINDOWS_CLIPBOARD]=${RUNTIME[WSL_PLUS_ALLOW_WINDOWS_CLIPBOARD]-0}
  RUNTIME[WSL_PLUS_ALLOW_WINDOWS_APP_LAUNCH]=${RUNTIME[WSL_PLUS_ALLOW_WINDOWS_APP_LAUNCH]-0}
  RUNTIME[WSL_PLUS_ALLOW_GIT_CREDENTIAL_BRIDGE]=${RUNTIME[WSL_PLUS_ALLOW_GIT_CREDENTIAL_BRIDGE]-0}
  RUNTIME[WSL_PLUS_ALLOW_CLOUD_HISTORY_SYNC]=${RUNTIME[WSL_PLUS_ALLOW_CLOUD_HISTORY_SYNC]-0}
  RUNTIME[WSL_PLUS_IMPORT_WINDOWS_PATH]=${RUNTIME[WSL_PLUS_IMPORT_WINDOWS_PATH]-0}
  RUNTIME[WSL_PLUS_ALLOW_WINDOWS_PATH_IMPORT]=${RUNTIME[WSL_PLUS_IMPORT_WINDOWS_PATH]-0}
  RUNTIME[WSL_PLUS_ENABLE_NAVIGATION_HELPERS]=${RUNTIME[WSL_PLUS_ENABLE_NAVIGATION_HELPERS]-0}
  if [[ ${RUNTIME[WSL_PLUS_POLICY]-} == home && ${RUNTIME[WSL_PLUS_ENABLE_HOME_SESSIONS]-0} == 1 ]]; then
    RUNTIME[WSL_PLUS_ENABLE_LOCAL_SESSIONS]=1
    RUNTIME[WSL_PLUS_SESSION_BACKEND]=auto
  else
    RUNTIME[WSL_PLUS_ENABLE_LOCAL_SESSIONS]=0
    RUNTIME[WSL_PLUS_SESSION_BACKEND]=native
  fi
elif [[ $schema == 2 ]]; then
  required_runtime_keys=(
    WSL_PLUS_SCHEMA_VERSION WSL_PLUS_VERSION WSL_PLUS_POLICY
    WSL_PLUS_INTEGRATION WSL_PLUS_MODE
    WSL_PLUS_ALLOW_WINDOWS_INTEROP WSL_PLUS_ALLOW_WINDOWS_AUTOMOUNT
    WSL_PLUS_ALLOW_CROSS_FILESYSTEM WSL_PLUS_ALLOW_WINDOWS_CLIPBOARD
    WSL_PLUS_ALLOW_WINDOWS_APP_LAUNCH WSL_PLUS_ALLOW_GIT_CREDENTIAL_BRIDGE
    WSL_PLUS_ALLOW_SHARED_SSH_AGENT WSL_PLUS_ALLOW_CLOUD_HISTORY_SYNC
    WSL_PLUS_ALLOW_WINDOWS_PATH_IMPORT WSL_PLUS_IMPORT_WINDOWS_PATH
    WSL_PLUS_ENABLE_FZF WSL_PLUS_ENABLE_BLESH WSL_PLUS_ENABLE_ZOXIDE
    WSL_PLUS_ENABLE_NAVIGATION_HELPERS WSL_PLUS_ENABLE_HISTORY_SETTINGS
    WSL_PLUS_ENABLE_HISTORY_PROMPT_HOOK WSL_PLUS_ENABLE_LOCAL_SESSIONS
    WSL_PLUS_SESSION_BACKEND WSL_PLUS_MANAGE_PROMPT WSL_PLUS_MANAGE_TMUX
    WSL_PLUS_PACKAGES_SKIPPED
  )
  if config_require_exact_keys RUNTIME "${required_runtime_keys[@]}"; then
    pass 'Runtime schema 2 contains exactly the supported keys'
  else
    fail 'Runtime schema 2 is incomplete or contains unsupported keys'
  fi
else
  fail "Unsupported runtime schema: $schema"
fi

runtime_bool_keys=(
  WSL_PLUS_ALLOW_WINDOWS_INTEROP WSL_PLUS_ALLOW_WINDOWS_AUTOMOUNT
  WSL_PLUS_ALLOW_CROSS_FILESYSTEM WSL_PLUS_ALLOW_WINDOWS_CLIPBOARD
  WSL_PLUS_ALLOW_WINDOWS_APP_LAUNCH WSL_PLUS_ALLOW_GIT_CREDENTIAL_BRIDGE
  WSL_PLUS_ALLOW_SHARED_SSH_AGENT WSL_PLUS_ALLOW_CLOUD_HISTORY_SYNC
  WSL_PLUS_ALLOW_WINDOWS_PATH_IMPORT WSL_PLUS_IMPORT_WINDOWS_PATH
  WSL_PLUS_ENABLE_FZF WSL_PLUS_ENABLE_BLESH WSL_PLUS_ENABLE_ZOXIDE
  WSL_PLUS_ENABLE_NAVIGATION_HELPERS WSL_PLUS_ENABLE_HISTORY_SETTINGS
  WSL_PLUS_ENABLE_HISTORY_PROMPT_HOOK WSL_PLUS_ENABLE_LOCAL_SESSIONS
  WSL_PLUS_MANAGE_PROMPT WSL_PLUS_MANAGE_TMUX WSL_PLUS_PACKAGES_SKIPPED
)
for key in "${runtime_bool_keys[@]}"; do
  config_bool RUNTIME "$key" >/dev/null || fail "Runtime key is not Boolean: $key"
done
if [[ ${RUNTIME[WSL_PLUS_SESSION_BACKEND]-} != auto \
  && ${RUNTIME[WSL_PLUS_SESSION_BACKEND]-} != native ]]; then
  fail "Unsupported runtime session backend: ${RUNTIME[WSL_PLUS_SESSION_BACKEND]-<missing>}"
fi

policy_id=${RUNTIME[WSL_PLUS_POLICY]-}
integration_id=${RUNTIME[WSL_PLUS_INTEGRATION]-}
mode=${RUNTIME[WSL_PLUS_MODE]-}
version=${RUNTIME[WSL_PLUS_VERSION]-}

if [[ -r $ROOT_DIR/VERSION && $(tr -d '[:space:]' < "$ROOT_DIR/VERSION") == "$version" ]]; then
  pass "Installed version is internally consistent: $version"
else
  fail 'Installed VERSION and runtime version differ'
fi

policy_file="$ROOT_DIR/policies/$policy_id.conf"
defaults_file="$ROOT_DIR/defaults/$policy_id.conf"
integration_dir="$ROOT_DIR/integrations/$integration_id"
integration_file="$integration_dir/integration.conf"

declare -A POLICY=()
declare -A DEFAULTS=()
declare -A INTEGRATION=()
if load_kv_config "$policy_file" POLICY &&
  load_kv_config "$defaults_file" DEFAULTS &&
  load_kv_config "$integration_file" INTEGRATION; then
  pass "Policy, defaults, and integration manifests load: $policy_id + $integration_id"
else
  fail 'Policy, defaults, or integration manifest cannot be loaded'
fi

policy_keys=(
  POLICY_ID ALLOW_WINDOWS_INTEROP ALLOW_WINDOWS_AUTOMOUNT
  ALLOW_CROSS_FILESYSTEM ALLOW_WINDOWS_CLIPBOARD
  ALLOW_WINDOWS_APP_LAUNCH ALLOW_GIT_CREDENTIAL_BRIDGE
  ALLOW_SHARED_SSH_AGENT ALLOW_CLOUD_HISTORY_SYNC
  ALLOW_WINDOWS_PATH_IMPORT
)
defaults_keys=(
  DEFAULTS_ID DEFAULT_MODE DEFAULT_INTEGRATION IMPORT_WINDOWS_PATH
  ENABLE_FZF ENABLE_BLESH ENABLE_ZOXIDE ENABLE_NAVIGATION_HELPERS
  ENABLE_HISTORY_SETTINGS ENABLE_HISTORY_PROMPT_HOOK
  ENABLE_LOCAL_SESSIONS SESSION_BACKEND MANAGE_PROMPT MANAGE_TMUX
)
integration_keys=(
  INTEGRATION_ID REQUIRED_POLICY PROTECTED_PATHS_FILE
  PROTECTED_COMMANDS_FILE CONTRACT_DIR CONTRACT_SCHEMA_VERSION
  CONTRACT_OWNER_COMMIT CONTRACT_PUBLICATION_COMMIT
)
config_require_exact_keys POLICY "${policy_keys[@]}" \
  || fail 'Policy manifest has missing or unsupported keys'
config_require_exact_keys DEFAULTS "${defaults_keys[@]}" \
  || fail 'Defaults manifest has missing or unsupported keys'
config_require_exact_keys INTEGRATION "${integration_keys[@]}" \
  || fail 'Integration manifest has missing or unsupported keys'
for key in "${policy_keys[@]:1}"; do
  config_bool POLICY "$key" >/dev/null || fail "Policy capability is not Boolean: $key"
done
for key in \
  IMPORT_WINDOWS_PATH ENABLE_FZF ENABLE_BLESH ENABLE_ZOXIDE \
  ENABLE_NAVIGATION_HELPERS ENABLE_HISTORY_SETTINGS \
  ENABLE_HISTORY_PROMPT_HOOK ENABLE_LOCAL_SESSIONS MANAGE_PROMPT \
  MANAGE_TMUX; do
  config_bool DEFAULTS "$key" >/dev/null || fail "Profile default is not Boolean: $key"
done
if [[ ${DEFAULTS[SESSION_BACKEND]-} != auto && ${DEFAULTS[SESSION_BACKEND]-} != native ]]; then
  fail "Unsupported profile session backend: ${DEFAULTS[SESSION_BACKEND]-<missing>}"
fi
if [[ ${DEFAULTS[IMPORT_WINDOWS_PATH]-0} == 1 && ${POLICY[ALLOW_WINDOWS_PATH_IMPORT]-0} != 1 ]]; then
  fail 'Profile defaults import Windows PATH while the policy capability is disabled'
fi

if [[ ${POLICY[POLICY_ID]-} == "$policy_id" ]]; then
  pass 'Policy ID matches runtime selection'
else
  fail 'Policy ID does not match runtime selection'
fi
if [[ ${DEFAULTS[DEFAULTS_ID]-} == "$policy_id" ]]; then
  pass 'Defaults ID matches runtime selection'
else
  fail 'Defaults ID does not match runtime selection'
fi
if [[ ${INTEGRATION[INTEGRATION_ID]-} == "$integration_id" ]]; then
  pass 'Integration ID matches runtime selection'
else
  fail 'Integration ID does not match runtime selection'
fi

if [[ -n ${INTEGRATION[REQUIRED_POLICY]-} && ${INTEGRATION[REQUIRED_POLICY]} != "$policy_id" ]]; then
  fail "Integration requires policy ${INTEGRATION[REQUIRED_POLICY]}"
fi

ETC_PREFIX=${WSL_PLUS_ETC_ROOT:-}
# Every integration that publishes a contract is swept, not just the selected
# one. If a site's deployment facts are on this machine while a weaker
# integration is selected, that is a misconfiguration worth reporting.
unselected_contract_integrations=0
for candidate_dir in "$ROOT_DIR"/integrations/*; do
  [[ -d $candidate_dir ]] || continue
  candidate_id=$(basename -- "$candidate_dir")
  [[ $candidate_id != "$integration_id" ]] || continue
  declare -A CANDIDATE_INTEGRATION=()
  # shellcheck disable=SC2034 # Consumed through namerefs in contract helpers.
  declare -A CANDIDATE_CONTRACT=()
  if ! load_kv_config "$candidate_dir/integration.conf" CANDIDATE_INTEGRATION     || ! config_require_exact_keys CANDIDATE_INTEGRATION "${integration_keys[@]}"; then
    fail "Integration metadata is invalid: $candidate_id"
    unset CANDIDATE_INTEGRATION CANDIDATE_CONTRACT
    continue
  fi
  if [[ -z ${CANDIDATE_INTEGRATION[CONTRACT_DIR]-} ]]; then
    unset CANDIDATE_INTEGRATION CANDIDATE_CONTRACT
    continue
  fi
  unselected_contract_integrations=$((unselected_contract_integrations + 1))
  candidate_contract_dir="$candidate_dir/${CANDIDATE_INTEGRATION[CONTRACT_DIR]}"
  if ! load_integration_contract "$candidate_contract_dir" CANDIDATE_CONTRACT; then
    fail "Protected-effects contract is invalid: $candidate_id"
  elif ! validate_integration_contract_pin CANDIDATE_INTEGRATION CANDIDATE_CONTRACT; then
    fail "Integration pin does not match its protected-effects contract: $candidate_id"
  else
    pass "Contract schema, hashes, owner baseline, and publication pin are valid: $candidate_id"
    if validate_installed_contract_layout "$candidate_contract_dir"; then
      pass "Installed contract ownership, modes, and non-symlink layout are valid: $candidate_id"
    else
      fail "Installed contract ownership, modes, or non-symlink layout is invalid: $candidate_id"
    fi
    candidate_detection=$(contract_detection_state "$candidate_contract_dir" CANDIDATE_CONTRACT "$ETC_PREFIX")
    case $candidate_detection in
      present) fail "Deployment facts for $candidate_id are present but $integration_id is selected" ;;
      partial) fail "Deployment facts for $candidate_id are partial or have unexpected types" ;;
      absent) info "No deployment facts were detected for $candidate_id." ;;
      *) fail "Unexpected detection state for $candidate_id: $candidate_detection" ;;
    esac
  fi
  unset CANDIDATE_INTEGRATION CANDIDATE_CONTRACT
done
if ((unselected_contract_integrations == 0)); then
  info 'No unselected integrations publish a protected-effects contract.'
fi

protected_commands_file=
if [[ -n ${INTEGRATION[CONTRACT_DIR]-} ]]; then
  selected_contract_dir="$integration_dir/${INTEGRATION[CONTRACT_DIR]}"
  # shellcheck disable=SC2034 # Consumed through namerefs in contract helpers.
  declare -A SELECTED_CONTRACT=()
  if load_integration_contract "$selected_contract_dir" SELECTED_CONTRACT \
    && validate_integration_contract_pin INTEGRATION SELECTED_CONTRACT; then
    pass "Contract schema, hashes, owner baseline, and publication pin are valid: $integration_id"
    if validate_installed_contract_layout "$selected_contract_dir"; then
      pass "Installed contract ownership, modes, and non-symlink layout are valid: $integration_id"
    else
      fail "Installed contract ownership, modes, or non-symlink layout is invalid: $integration_id"
    fi
    selected_paths_file="$doctor_tmp/protected-paths.txt"
    protected_commands_file="$doctor_tmp/protected-commands.txt"
    contract_materialize_effect_lists "$selected_contract_dir" SELECTED_CONTRACT \
      "$selected_paths_file" "$protected_commands_file"
  else
    fail 'Selected integration contract is invalid or stale'
  fi
else
  protected_commands_file="$integration_dir/${INTEGRATION[PROTECTED_COMMANDS_FILE]-}"
fi

runtime_policy_pairs=(
  'ALLOW_WINDOWS_INTEROP:WSL_PLUS_ALLOW_WINDOWS_INTEROP'
  'ALLOW_WINDOWS_AUTOMOUNT:WSL_PLUS_ALLOW_WINDOWS_AUTOMOUNT'
  'ALLOW_CROSS_FILESYSTEM:WSL_PLUS_ALLOW_CROSS_FILESYSTEM'
  'ALLOW_WINDOWS_CLIPBOARD:WSL_PLUS_ALLOW_WINDOWS_CLIPBOARD'
  'ALLOW_WINDOWS_APP_LAUNCH:WSL_PLUS_ALLOW_WINDOWS_APP_LAUNCH'
  'ALLOW_GIT_CREDENTIAL_BRIDGE:WSL_PLUS_ALLOW_GIT_CREDENTIAL_BRIDGE'
  'ALLOW_SHARED_SSH_AGENT:WSL_PLUS_ALLOW_SHARED_SSH_AGENT'
  'ALLOW_CLOUD_HISTORY_SYNC:WSL_PLUS_ALLOW_CLOUD_HISTORY_SYNC'
  'ALLOW_WINDOWS_PATH_IMPORT:WSL_PLUS_ALLOW_WINDOWS_PATH_IMPORT'
)
for pair in "${runtime_policy_pairs[@]}"; do
  policy_key=${pair%%:*}
  runtime_key=${pair#*:}
  if [[ ${POLICY[$policy_key]-} != "${RUNTIME[$runtime_key]-}" ]]; then
    fail "Runtime $runtime_key diverges from policy capability $policy_key"
  fi
done

if [[ $schema == 2 ]]; then
  runtime_default_pairs=(
    'IMPORT_WINDOWS_PATH:WSL_PLUS_IMPORT_WINDOWS_PATH'
    'ENABLE_FZF:WSL_PLUS_ENABLE_FZF'
    'ENABLE_BLESH:WSL_PLUS_ENABLE_BLESH'
    'ENABLE_ZOXIDE:WSL_PLUS_ENABLE_ZOXIDE'
    'ENABLE_NAVIGATION_HELPERS:WSL_PLUS_ENABLE_NAVIGATION_HELPERS'
    'ENABLE_HISTORY_SETTINGS:WSL_PLUS_ENABLE_HISTORY_SETTINGS'
    'ENABLE_HISTORY_PROMPT_HOOK:WSL_PLUS_ENABLE_HISTORY_PROMPT_HOOK'
    'ENABLE_LOCAL_SESSIONS:WSL_PLUS_ENABLE_LOCAL_SESSIONS'
    'SESSION_BACKEND:WSL_PLUS_SESSION_BACKEND'
    'MANAGE_PROMPT:WSL_PLUS_MANAGE_PROMPT'
    'MANAGE_TMUX:WSL_PLUS_MANAGE_TMUX'
  )
  for pair in "${runtime_default_pairs[@]}"; do
    default_key=${pair%%:*}
    runtime_key=${pair#*:}
    if [[ ${DEFAULTS[$default_key]-} != "${RUNTIME[$runtime_key]-}" ]]; then
      fail "Runtime $runtime_key diverges from profile default $default_key"
    fi
  done
fi

check_file_marker "$HOME/.bashrc" "$WSL_PLUS_BEGIN_MARKER" "$WSL_PLUS_END_MARKER" '.bashrc'
if [[ ${RUNTIME[WSL_PLUS_MANAGE_TMUX]-0} == 1 ]]; then
  check_file_marker "$HOME/.tmux.conf" "$WSL_PLUS_TMUX_BEGIN_MARKER" "$WSL_PLUS_TMUX_END_MARKER" '.tmux.conf'
fi

if [[ -x $HOME/.local/bin/wsl-plus && -x $ROOT_DIR/bin/wsl-plus ]]; then
  pass 'Stable absolute wsl-plus wrapper is installed'
else
  fail 'Stable absolute wsl-plus wrapper is missing or not executable'
fi

bash_parse_ok=1
bash_files=(
  "$ROOT_DIR/install.sh" "$ROOT_DIR/doctor.sh" "$ROOT_DIR/rollback.sh"
  "$ROOT_DIR/bin/wsl-plus" "$ROOT_DIR/bin/wsl-plus-session"
  "$ROOT_DIR/bin/wsl-plus-ssh-agent" "$ROOT_DIR/core/bash/blesh.rc"
  "$ROOT_DIR/core/bash/"*.bash "$ROOT_DIR/lib/"*.sh
)
for bash_file in "${bash_files[@]}"; do
  if ! bash -n "$bash_file"; then
    bash_parse_ok=0
  fi
done
if [[ $bash_parse_ok == 1 ]]; then
  pass 'Installed shell entry points parse successfully'
else
  fail 'One or more installed shell entry points have syntax errors'
fi

if [[ ${RUNTIME[WSL_PLUS_ENABLE_BLESH]-0} == 1 ]]; then
  blesh_path=
  for candidate in \
    "${XDG_DATA_HOME:-$HOME/.local/share}/blesh/ble.sh" \
    /usr/local/share/blesh/ble.sh /usr/share/blesh/ble.sh; do
    if [[ -r $candidate ]]; then blesh_path=$candidate; break; fi
  done
  if [[ -n $blesh_path ]]; then
    pass "Automatic Bash suggestions are available through ble.sh: $blesh_path"
  else
    info 'Automatic Bash suggestions are enabled but ble.sh is not installed.'
  fi
fi

ssh_capabilities=0
if [[ ${RUNTIME[WSL_PLUS_ALLOW_SHARED_SSH_AGENT]-0} == 1 &&
  ${RUNTIME[WSL_PLUS_ALLOW_WINDOWS_INTEROP]-0} == 1 &&
  ${RUNTIME[WSL_PLUS_ALLOW_CROSS_FILESYSTEM]-0} == 1 ]]; then
  ssh_capabilities=1
fi
if [[ $ssh_capabilities == 1 ]]; then
  pass 'Windows SSH-agent adapter is permitted by all required capabilities'
  ssh_agent_status=$("$ROOT_DIR/bin/wsl-plus-ssh-agent" status 2>&1) || {
    fail 'Windows SSH-agent status command failed'
    ssh_agent_status=
  }
  [[ -z $ssh_agent_status ]] || printf '       %s\n' "$ssh_agent_status"
else
  pass 'Windows SSH-agent adapter is disabled by capabilities'
fi

if [[ ${RUNTIME[WSL_PLUS_ENABLE_LOCAL_SESSIONS]-0} == 1 ]]; then
  if [[ -x $ROOT_DIR/bin/wsl-plus-session ]]; then
    pass 'Local session command is installed'
  else
    fail 'Local session command is missing or not executable'
  fi
  if [[ -r $ROOT_DIR/core/tmux/local-sessions.conf ]]; then
    pass 'Bounded local tmux configuration is installed'
  else
    fail 'Bounded local tmux configuration is missing'
  fi
  if grep -Fq 'core/tmux/local-sessions.conf' "$HOME/.tmux.conf" 2>/dev/null; then
    pass 'Bounded local tmux configuration is sourced'
  else
    fail 'Bounded local tmux configuration is not sourced'
  fi

  if [[ ${RUNTIME[WSL_PLUS_SESSION_BACKEND]-} == auto ]]; then
    if [[ -r $ROOT_DIR/core/session/sesh.toml ]]; then
      pass 'Optional safe Sesh configuration is installed'
    else
      fail 'Optional safe Sesh configuration is missing'
    fi
    if grep -Fq 'core/tmux/home-sessions.conf' "$HOME/.tmux.conf" 2>/dev/null; then
      pass 'Optional Home session adapters are sourced for the auto backend'
    else
      fail 'Optional Home session adapters are not sourced for the auto backend'
    fi
  elif [[ ${RUNTIME[WSL_PLUS_SESSION_BACKEND]-} == native ]]; then
    if grep -Fq 'core/tmux/home-sessions.conf' "$HOME/.tmux.conf" 2>/dev/null; then
      fail 'External Home session adapters are sourced for the native backend'
    else
      pass 'Native session backend excludes Sesh and tmux-resurrect adapters'
    fi
  else
    fail "Unsupported session backend: ${RUNTIME[WSL_PLUS_SESSION_BACKEND]-<missing>}"
  fi

  session_status=$("$ROOT_DIR/bin/wsl-plus-session" status 2>&1) || {
    fail 'Local session status command failed'
    session_status=
  }
  if [[ -n $session_status ]]; then
    while IFS= read -r status_line; do printf '       %s\n' "$status_line"; done <<< "$session_status"
  fi
elif grep -Fq 'core/tmux/local-sessions.conf' "$HOME/.tmux.conf" 2>/dev/null; then
  fail 'Local tmux configuration is sourced while local sessions are disabled'
fi

expected_commands=(git rg jq tmux shellcheck)
[[ ${RUNTIME[WSL_PLUS_ENABLE_FZF]-0} == 1 ]] && expected_commands+=(fzf)
[[ ${RUNTIME[WSL_PLUS_ENABLE_ZOXIDE]-0} == 1 ]] && expected_commands+=(zoxide)
for command_name in "${expected_commands[@]}"; do
  if command -v "$command_name" >/dev/null 2>&1; then
    pass "Command available: $command_name"
  elif [[ ${RUNTIME[WSL_PLUS_PACKAGES_SKIPPED]-0} == 1 ]]; then
    warn "Enabled command is unavailable after --skip-packages: $command_name"
  else
    fail "Expected command is unavailable: $command_name"
  fi
done

machine_lock="$ETC_PREFIX/etc/wsl-plus/machine-policy.conf"
if [[ -e $machine_lock ]]; then
  info "Deprecated machine lock is preserved but does not control installation: $machine_lock"
else
  pass 'No deprecated machine lock is present'
fi

if [[ ${RUNTIME[WSL_PLUS_ALLOW_WINDOWS_AUTOMOUNT]-0} == 0 ||
  ${RUNTIME[WSL_PLUS_ALLOW_CROSS_FILESYSTEM]-0} == 0 ]]; then
  mapfile -t detected_mounts < <(windows_mount_targets)
  if ((${#detected_mounts[@]})); then
    fail "Windows drive mounts are available despite disabled capabilities: ${detected_mounts[*]}"
  else
    pass 'Windows drive mounts are unavailable as required by capabilities'
  fi
fi

if [[ ${RUNTIME[WSL_PLUS_ALLOW_WINDOWS_INTEROP]-0} == 0 ]]; then
  mapfile -t detected_windows_commands < <(windows_executable_targets)
  if ((${#detected_windows_commands[@]})); then
    fail "Windows executable interop is available despite a disabled capability: ${detected_windows_commands[*]}"
  else
    pass 'Listed Windows executable interop commands are unavailable'
  fi
fi

if [[ -r $protected_commands_file ]]; then
  shell_enabled=$(mktemp)
  shell_disabled=$(mktemp)
  if capture_shell_state "$shell_enabled" "$protected_commands_file" 0 &&
    capture_shell_state "$shell_disabled" "$protected_commands_file" 1; then
    if cmp -s "$shell_disabled" "$shell_enabled"; then
      pass 'WSL Plus does not change current PATH or protected command resolution'
    else
      diff -u "$shell_disabled" "$shell_enabled" >&2 || true
      fail 'WSL Plus changes current PATH or protected command resolution'
    fi
  else
    fail 'Could not capture current shell causality state'
  fi
  rm -f -- "$shell_enabled" "$shell_disabled"
else
  fail "Protected command manifest is missing: $protected_commands_file"
fi

if [[ ${RUNTIME[WSL_PLUS_ALLOW_CROSS_FILESYSTEM]-0} == 1 ]]; then
  if [[ -d /mnt/c ]]; then
    pass 'Policy permits cross-filesystem access and /mnt/c is available'
  else
    info 'Policy permits cross-filesystem access, but /mnt/c is unavailable.'
  fi
fi

printf '\nDoctor finished with %d failure(s) and %d warning(s).\n' "$failures" "$warnings"
((failures == 0))
