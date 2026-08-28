#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/config.sh
. "$ROOT_DIR/lib/config.sh"
# shellcheck source=lib/integration-contract.sh
. "$ROOT_DIR/lib/integration-contract.sh"

usage() {
  cat <<'HELP'
usage: ./install.sh [OPTIONS]

Options:
  --policy home|restricted   Site policy. Default: home.
  --integration NAME         Environment integration. Defaults from profile.
  --mode managed|augment     Shell management mode. Defaults from profile.
  --check                    Print a deterministic plan and make no changes.
  --apply-plan SHA256        Verify and apply a previously printed plan.
  --skip-packages            Do not install APT packages.
  --help                     Show this help.

The check/apply flow is optional for every profile. If --apply-plan is given,
the installer rejects any plan that no longer matches current inputs.
HELP
}

policy_id=home
integration_id=
mode=
check_only=0
apply_plan=
skip_packages=0

while (($#)); do
  case $1 in
    --policy)
      [[ $# -ge 2 ]] || die '--policy requires a value'
      policy_id=$2
      shift 2
      ;;
    --integration)
      [[ $# -ge 2 ]] || die '--integration requires a value'
      integration_id=$2
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || die '--mode requires a value'
      mode=$2
      shift 2
      ;;
    --check)
      check_only=1
      shift
      ;;
    --apply-plan)
      [[ $# -ge 2 ]] || die '--apply-plan requires a value'
      apply_plan=$2
      shift 2
      ;;
    --skip-packages)
      skip_packages=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[[ $policy_id =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Invalid policy name: $policy_id"
[[ -r $ROOT_DIR/VERSION ]] || die 'VERSION file is missing'
version=$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")

if ! is_wsl && [[ ${WSL_PLUS_ALLOW_NON_WSL:-0} != 1 ]]; then
  die 'This installer must run inside WSL. Tests may set WSL_PLUS_ALLOW_NON_WSL=1.'
fi

policy_file="$ROOT_DIR/policies/$policy_id.conf"
defaults_file="$ROOT_DIR/defaults/$policy_id.conf"
declare -A POLICY=()
declare -A DEFAULTS=()
load_kv_config "$policy_file" POLICY || exit 1
load_kv_config "$defaults_file" DEFAULTS || exit 1
config_require_exact_keys POLICY \
  POLICY_ID \
  ALLOW_WINDOWS_INTEROP ALLOW_WINDOWS_AUTOMOUNT ALLOW_CROSS_FILESYSTEM \
  ALLOW_WINDOWS_CLIPBOARD ALLOW_WINDOWS_APP_LAUNCH \
  ALLOW_GIT_CREDENTIAL_BRIDGE ALLOW_SHARED_SSH_AGENT \
  ALLOW_CLOUD_HISTORY_SYNC ALLOW_WINDOWS_PATH_IMPORT || exit 1
config_require_exact_keys DEFAULTS \
  DEFAULTS_ID DEFAULT_MODE DEFAULT_INTEGRATION IMPORT_WINDOWS_PATH \
  ENABLE_FZF ENABLE_BLESH ENABLE_ZOXIDE ENABLE_NAVIGATION_HELPERS \
  ENABLE_HISTORY_SETTINGS ENABLE_HISTORY_PROMPT_HOOK \
  ENABLE_LOCAL_SESSIONS SESSION_BACKEND MANAGE_PROMPT MANAGE_TMUX || exit 1

[[ ${POLICY[POLICY_ID]} == "$policy_id" ]] || die "Policy ID mismatch in $policy_file"
[[ ${DEFAULTS[DEFAULTS_ID]} == "$policy_id" ]] || die "Defaults ID mismatch in $defaults_file"

for key in \
  ALLOW_WINDOWS_INTEROP ALLOW_WINDOWS_AUTOMOUNT ALLOW_CROSS_FILESYSTEM \
  ALLOW_WINDOWS_CLIPBOARD ALLOW_WINDOWS_APP_LAUNCH \
  ALLOW_GIT_CREDENTIAL_BRIDGE ALLOW_SHARED_SSH_AGENT \
  ALLOW_CLOUD_HISTORY_SYNC ALLOW_WINDOWS_PATH_IMPORT; do
  config_bool POLICY "$key" >/dev/null || exit 1
done
for key in \
  IMPORT_WINDOWS_PATH ENABLE_FZF ENABLE_BLESH ENABLE_ZOXIDE \
  ENABLE_NAVIGATION_HELPERS ENABLE_HISTORY_SETTINGS \
  ENABLE_HISTORY_PROMPT_HOOK ENABLE_LOCAL_SESSIONS MANAGE_PROMPT \
  MANAGE_TMUX; do
  config_bool DEFAULTS "$key" >/dev/null || exit 1
done
[[ ${DEFAULTS[SESSION_BACKEND]} == auto || ${DEFAULTS[SESSION_BACKEND]} == native ]] \
  || die "Unsupported session backend: ${DEFAULTS[SESSION_BACKEND]}"
if [[ ${DEFAULTS[IMPORT_WINDOWS_PATH]} == 1 && ${POLICY[ALLOW_WINDOWS_PATH_IMPORT]} != 1 ]]; then
  die 'Profile defaults cannot import Windows PATH when the policy capability is disabled.'
fi

integration_id=${integration_id:-${DEFAULTS[DEFAULT_INTEGRATION]}}
mode=${mode:-${DEFAULTS[DEFAULT_MODE]}}
[[ $integration_id =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Invalid integration name: $integration_id"
[[ $mode == managed || $mode == augment ]] || die "Unsupported mode: $mode"

integration_dir="$ROOT_DIR/integrations/$integration_id"
integration_file="$integration_dir/integration.conf"
declare -A INTEGRATION=()
load_kv_config "$integration_file" INTEGRATION || exit 1
config_require_exact_keys INTEGRATION \
  INTEGRATION_ID REQUIRED_POLICY PROTECTED_PATHS_FILE \
  PROTECTED_COMMANDS_FILE CONTRACT_DIR CONTRACT_SCHEMA_VERSION \
  CONTRACT_OWNER_COMMIT CONTRACT_PUBLICATION_COMMIT || exit 1

[[ ${INTEGRATION[INTEGRATION_ID]} == "$integration_id" ]] || die "Integration ID mismatch in $integration_file"
if [[ -n ${INTEGRATION[REQUIRED_POLICY]} && ${INTEGRATION[REQUIRED_POLICY]} != "$policy_id" ]]; then
  die "Integration $integration_id requires policy ${INTEGRATION[REQUIRED_POLICY]}"
fi
DATA_ROOT="$HOME/.local/share/wsl-plus"
CONFIG_ROOT="$HOME/.config/wsl-plus"
STATE_ROOT="$HOME/.local/state/wsl-plus"
BIN_PATH="$HOME/.local/bin/wsl-plus"
BASH_RC="$HOME/.bashrc"
TMUX_RC="$HOME/.tmux.conf"
ETC_PREFIX=${WSL_PLUS_ETC_ROOT:-}
MACHINE_LOCK="$ETC_PREFIX/etc/wsl-plus/machine-policy.conf"

plan_tmp=$(mktemp -d)
trap 'rm -rf -- "$plan_tmp"' EXIT

# Every integration that publishes a contract is evaluated, not just the
# selected one. A site's deployment facts on this machine decide whether the
# requested selection would be an unsafe misclassification.
for candidate_dir in "$ROOT_DIR"/integrations/*; do
  [[ -d $candidate_dir ]] || continue
  candidate_id=$(basename -- "$candidate_dir")
  [[ $candidate_id != "$integration_id" ]] || continue
  declare -A CANDIDATE_INTEGRATION=()
  # shellcheck disable=SC2034 # Consumed through namerefs in contract helpers.
  declare -A CANDIDATE_CONTRACT=()
  load_kv_config "$candidate_dir/integration.conf" CANDIDATE_INTEGRATION || exit 1
  config_require_exact_keys CANDIDATE_INTEGRATION     INTEGRATION_ID REQUIRED_POLICY PROTECTED_PATHS_FILE     PROTECTED_COMMANDS_FILE CONTRACT_DIR CONTRACT_SCHEMA_VERSION     CONTRACT_OWNER_COMMIT CONTRACT_PUBLICATION_COMMIT || exit 1
  [[ ${CANDIDATE_INTEGRATION[INTEGRATION_ID]} == "$candidate_id" ]]     || die "Integration ID mismatch in $candidate_dir/integration.conf"
  if [[ -z ${CANDIDATE_INTEGRATION[CONTRACT_DIR]} ]]; then
    unset CANDIDATE_INTEGRATION CANDIDATE_CONTRACT
    continue
  fi
  candidate_contract_dir="$candidate_dir/${CANDIDATE_INTEGRATION[CONTRACT_DIR]}"
  load_integration_contract "$candidate_contract_dir" CANDIDATE_CONTRACT || exit 1
  validate_integration_contract_pin CANDIDATE_INTEGRATION CANDIDATE_CONTRACT || exit 1
  candidate_detection=$(contract_detection_state "$candidate_contract_dir" CANDIDATE_CONTRACT "$ETC_PREFIX")
  case $candidate_detection in
    present)
      die "Deployment facts for $candidate_id are present; select --policy ${CANDIDATE_INTEGRATION[REQUIRED_POLICY]:-<its policy>} --integration $candidate_id."
      ;;
    partial)
      die "Deployment facts for $candidate_id are partial or have unexpected types; no installation changes were made."
      ;;
    absent) ;;
    *) die "Unexpected detection state for $candidate_id: $candidate_detection" ;;
  esac
  unset CANDIDATE_INTEGRATION CANDIDATE_CONTRACT
done

if [[ -n ${INTEGRATION[CONTRACT_DIR]} ]]; then
  selected_contract_dir="$integration_dir/${INTEGRATION[CONTRACT_DIR]}"
  # shellcheck disable=SC2034 # Consumed through namerefs in contract helpers.
  declare -A SELECTED_CONTRACT=()
  load_integration_contract "$selected_contract_dir" SELECTED_CONTRACT || exit 1
  validate_integration_contract_pin INTEGRATION SELECTED_CONTRACT || exit 1
  protected_paths_file="$plan_tmp/protected-paths.txt"
  protected_commands_file="$plan_tmp/protected-commands.txt"
  protected_set_label="$selected_contract_dir/effects.tsv"
  contract_materialize_effect_lists "$selected_contract_dir" SELECTED_CONTRACT \
    "$protected_paths_file" "$protected_commands_file"
else
  protected_paths_file="$integration_dir/${INTEGRATION[PROTECTED_PATHS_FILE]}"
  protected_commands_file="$integration_dir/${INTEGRATION[PROTECTED_COMMANDS_FILE]}"
  [[ -r $protected_paths_file ]] || die "Protected path manifest is missing: $protected_paths_file"
  [[ -r $protected_commands_file ]] || die "Protected command manifest is missing: $protected_commands_file"
  protected_set_label="$protected_paths_file"
fi

proposed_paths=(
  "$DATA_ROOT"
  "$CONFIG_ROOT"
  "$STATE_ROOT"
  "$BASH_RC"
  "$TMUX_RC"
  "$BIN_PATH"
)

declare -a protected_paths=()
read_list_file "$protected_paths_file" protected_paths
for proposed in "${proposed_paths[@]}"; do
  for protected_raw in "${protected_paths[@]}"; do
    protected=$(expand_path_token "$protected_raw")
    if path_is_within "$proposed" "$protected"; then
      die "Planned write path falls within integration-protected path: $proposed -> $protected"
    fi
  done
done

if [[ ${POLICY[ALLOW_WINDOWS_AUTOMOUNT]} == 0 || ${POLICY[ALLOW_CROSS_FILESYSTEM]} == 0 ]]; then
  mapfile -t detected_mounts < <(windows_mount_targets)
  ((${#detected_mounts[@]} == 0)) \
    || die "Policy preflight failed: Windows drive mounts are available: ${detected_mounts[*]}"
fi
if [[ ${POLICY[ALLOW_WINDOWS_INTEROP]} == 0 ]]; then
  mapfile -t detected_windows_commands < <(windows_executable_targets)
  ((${#detected_windows_commands[@]} == 0)) \
    || die "Policy preflight failed: Windows executable interop is available: ${detected_windows_commands[*]}"
fi

transaction_active=0

cleanup_exit() {
  local status=$?
  trap - EXIT
  set +e

  if [[ $status -ne 0 && ${transaction_active:-0} == 1 ]]; then
    rollback_transaction
  fi

  rm -rf -- "${plan_tmp:-}"
  exit "$status"
}

trap cleanup_exit EXIT
trap 'exit 130' INT TERM

capture_protected_fingerprint "$protected_paths_file" "$plan_tmp/protected.before"
capture_shell_state "$plan_tmp/shell.plan" "$protected_commands_file" 1

bashrc_sha=$(sha256_file_or_absent "$BASH_RC")
tmux_sha=$(sha256_file_or_absent "$TMUX_RC")
wsl_conf_sha=$(sha256_file_or_absent "$ETC_PREFIX/etc/wsl.conf")
lock_sha=$(sha256_file_or_absent "$MACHINE_LOCK")
policy_sha=$(sha256_file_or_absent "$policy_file")
defaults_sha=$(sha256_file_or_absent "$defaults_file")
integration_sha=$(sha256_file_or_absent "$integration_file")
paths_sha=$(sha256_file_or_absent "$protected_paths_file")
commands_sha=$(sha256_file_or_absent "$protected_commands_file")
shell_sha=$(sha256_file_or_absent "$plan_tmp/shell.plan")
protected_sha=$(sha256_file_or_absent "$plan_tmp/protected.before")

plan_material=$(cat <<EOF_PLAN
version=$version
policy=$policy_id
integration=$integration_id
mode=$mode
skip_packages=$skip_packages
uid=$(id -u)
home=$HOME
bashrc=$bashrc_sha
tmux=$tmux_sha
wsl_conf=$wsl_conf_sha
machine_lock=$lock_sha
policy_file=$policy_sha
defaults_file=$defaults_sha
integration_file=$integration_sha
protected_paths=$paths_sha
protected_commands=$commands_sha
shell_state=$shell_sha
protected_state=$protected_sha
EOF_PLAN
)
plan_id=$(printf '%s' "$plan_material" | sha256_text)

print_plan() {
  cat <<EOF_PLAN
WSL Plus installation plan

  Version:       $version
  Policy:        $policy_id
  Integration:   $integration_id
  Mode:          $mode
  Package step:  $([[ $skip_packages == 1 ]] && printf 'skipped' || printf 'APT base plus available optional packages')
  Shell update:  marker-bounded additive source in $BASH_RC
  Tmux update:   $([[ ${DEFAULTS[MANAGE_TMUX]} == 1 ]] && printf 'marker-bounded additive source in %s' "$TMUX_RC" || printf 'disabled')
  Local sessions:$([[ ${DEFAULTS[ENABLE_LOCAL_SESSIONS]} == 1 ]] && printf ' enabled (%s backend)' "${DEFAULTS[SESSION_BACKEND]}" || printf ' disabled')
  Prompt:        $([[ ${DEFAULTS[MANAGE_PROMPT]} == 1 ]] && printf 'managed' || printf 'preserved')
  PATH:          not rewritten; enabled/disabled shells must resolve identically
  Legacy lock:   $([[ -e $MACHINE_LOCK ]] && printf 'preserved as deprecated state at %s' "$MACHINE_LOCK" || printf 'none; no lock will be created')
  Protected set: $protected_set_label
  Plan ID:       $plan_id

The installer does not modify /etc/wsl.conf, agent routes, MCP settings,
Claude or Codex configuration, credential helpers, SSH configuration, or Git
worktrees. Package installation and the listed marker-bounded user files are
the only planned mutations.
EOF_PLAN
}

print_plan

if [[ $check_only == 1 ]]; then
  exit 0
fi

if [[ -n $apply_plan && $apply_plan != "$plan_id" ]]; then
  die "Plan mismatch. Current plan ID: $plan_id"
fi

transaction_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
backup_dir="$STATE_ROOT/backups/$transaction_id"

rollback_transaction() {
  set +e
  transaction_active=0
  log_warn 'Installation failed. Restoring user-level files from the transaction backup.'
  restore_backup "$DATA_ROOT/current" "$backup_dir" data-current
  restore_backup "$CONFIG_ROOT" "$backup_dir" config-root
  restore_backup "$BIN_PATH" "$backup_dir" bin-wsl-plus
  restore_backup "$BASH_RC" "$backup_dir" bashrc
  restore_backup "$TMUX_RC" "$backup_dir" tmuxrc

}

mkdir -p "$backup_dir"
backup_if_present "$DATA_ROOT/current" "$backup_dir" data-current
backup_if_present "$CONFIG_ROOT" "$backup_dir" config-root
backup_if_present "$BIN_PATH" "$backup_dir" bin-wsl-plus
backup_if_present "$BASH_RC" "$backup_dir" bashrc
backup_if_present "$TMUX_RC" "$backup_dir" tmuxrc
transaction_active=1

install_packages() {
  [[ $skip_packages == 0 ]] || {
    log_info 'Skipping package installation.'
    return 0
  }

  command_exists apt-get || die 'APT was not found. WSL Plus supports Ubuntu and Debian WSL.'

  local -a base_packages=()
  local -a optional_packages=()
  local -a available_optional=()
  local package candidate
  mapfile -t base_packages < <(grep -Ev '^[[:space:]]*(#|$)' "$ROOT_DIR/packages/base.apt")
  mapfile -t optional_packages < <(grep -Ev '^[[:space:]]*(#|$)' "$ROOT_DIR/packages/optional.apt")

  if [[ $(id -u) -eq 0 ]]; then
    apt-get update
    env DEBIAN_FRONTEND=noninteractive apt-get install -y "${base_packages[@]}"
  else
    command_exists sudo || die 'sudo is required for package installation. Use --skip-packages to omit it.'
    sudo apt-get update
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${base_packages[@]}"
  fi

  for package in "${optional_packages[@]}"; do
    candidate=$(
      LC_ALL=C apt-cache policy "$package" 2>/dev/null |
        sed -n 's/^[[:space:]]*Candidate:[[:space:]]*//p'
    )
    if [[ -n $candidate && $candidate != '(none)' ]]; then
      available_optional+=("$package")
    fi
  done

  if ((${#available_optional[@]})); then
    if [[ $(id -u) -eq 0 ]]; then
      env DEBIAN_FRONTEND=noninteractive apt-get install -y "${available_optional[@]}"
    else
      sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${available_optional[@]}"
    fi
  fi
}

install_packages

# Package installation is an authorized, separate mutation class. Capture the
# shell causality baseline only after it finishes so a newly installed command
# is not misattributed to WSL Plus's marker-bounded shell changes.
capture_shell_state "$plan_tmp/shell.causality-before" "$protected_commands_file" 1

log_info 'Installing versioned user files.'
mkdir -p "$DATA_ROOT" "$CONFIG_ROOT"
mkdir -p "$(dirname "$BIN_PATH")"
staging_dir=$(mktemp -d "$DATA_ROOT/.current.XXXXXX")
for item in VERSION install.sh doctor.sh rollback.sh bin core defaults integrations lib packages policies docs; do
  cp -a -- "$ROOT_DIR/$item" "$staging_dir/"
done
# Normalize permissions on any integration-owned contract directory so a
# published contract cannot be installed with surprising modes.
for contract_root in "$staging_dir"/integrations/*/contracts; do
  [[ -d $contract_root ]] || continue
  find "$contract_root" -type d -exec chmod 0755 {} +
  find "$contract_root" -type f -exec chmod 0644 {} +
done
rm -rf -- "$DATA_ROOT/current.previous"
if [[ -e $DATA_ROOT/current ]]; then
  mv -- "$DATA_ROOT/current" "$DATA_ROOT/current.previous"
fi
mv -- "$staging_dir" "$DATA_ROOT/current"

runtime_tmp=$(mktemp "$CONFIG_ROOT/runtime.conf.XXXXXX")
cat > "$runtime_tmp" <<EOF_RUNTIME
WSL_PLUS_SCHEMA_VERSION=2
WSL_PLUS_VERSION=$version
WSL_PLUS_POLICY=$policy_id
WSL_PLUS_INTEGRATION=$integration_id
WSL_PLUS_MODE=$mode
WSL_PLUS_ALLOW_WINDOWS_INTEROP=${POLICY[ALLOW_WINDOWS_INTEROP]}
WSL_PLUS_ALLOW_WINDOWS_AUTOMOUNT=${POLICY[ALLOW_WINDOWS_AUTOMOUNT]}
WSL_PLUS_ALLOW_CROSS_FILESYSTEM=${POLICY[ALLOW_CROSS_FILESYSTEM]}
WSL_PLUS_ALLOW_WINDOWS_CLIPBOARD=${POLICY[ALLOW_WINDOWS_CLIPBOARD]}
WSL_PLUS_ALLOW_WINDOWS_APP_LAUNCH=${POLICY[ALLOW_WINDOWS_APP_LAUNCH]}
WSL_PLUS_ALLOW_GIT_CREDENTIAL_BRIDGE=${POLICY[ALLOW_GIT_CREDENTIAL_BRIDGE]}
WSL_PLUS_ALLOW_SHARED_SSH_AGENT=${POLICY[ALLOW_SHARED_SSH_AGENT]}
WSL_PLUS_ALLOW_CLOUD_HISTORY_SYNC=${POLICY[ALLOW_CLOUD_HISTORY_SYNC]}
WSL_PLUS_ALLOW_WINDOWS_PATH_IMPORT=${POLICY[ALLOW_WINDOWS_PATH_IMPORT]}
WSL_PLUS_IMPORT_WINDOWS_PATH=${DEFAULTS[IMPORT_WINDOWS_PATH]}
WSL_PLUS_ENABLE_FZF=${DEFAULTS[ENABLE_FZF]}
WSL_PLUS_ENABLE_BLESH=${DEFAULTS[ENABLE_BLESH]}
WSL_PLUS_ENABLE_ZOXIDE=${DEFAULTS[ENABLE_ZOXIDE]}
WSL_PLUS_ENABLE_NAVIGATION_HELPERS=${DEFAULTS[ENABLE_NAVIGATION_HELPERS]}
WSL_PLUS_ENABLE_HISTORY_SETTINGS=${DEFAULTS[ENABLE_HISTORY_SETTINGS]}
WSL_PLUS_ENABLE_HISTORY_PROMPT_HOOK=${DEFAULTS[ENABLE_HISTORY_PROMPT_HOOK]}
WSL_PLUS_ENABLE_LOCAL_SESSIONS=${DEFAULTS[ENABLE_LOCAL_SESSIONS]}
WSL_PLUS_SESSION_BACKEND=${DEFAULTS[SESSION_BACKEND]}
WSL_PLUS_MANAGE_PROMPT=${DEFAULTS[MANAGE_PROMPT]}
WSL_PLUS_MANAGE_TMUX=${DEFAULTS[MANAGE_TMUX]}
WSL_PLUS_PACKAGES_SKIPPED=$skip_packages
EOF_RUNTIME
chmod 0600 "$runtime_tmp"
mv -- "$runtime_tmp" "$CONFIG_ROOT/runtime.conf"

cat > "$CONFIG_ROOT/init.bash" <<'EOF_INIT'
# shellcheck shell=bash
export WSL_PLUS_ROOT="$HOME/.local/share/wsl-plus/current"
export WSL_PLUS_RUNTIME="$HOME/.config/wsl-plus/runtime.conf"
# shellcheck disable=SC1091
. "$WSL_PLUS_ROOT/core/bash/init.bash"
EOF_INIT
chmod 0644 "$CONFIG_ROOT/init.bash"

install -m 0755 "$DATA_ROOT/current/bin/wsl-plus" "$BIN_PATH"

# shellcheck disable=SC2016 # Installed literally for the future interactive shell.
bash_block='if [ "${WSL_PLUS_DISABLE:-0}" != 1 ] && [ -r "$HOME/.config/wsl-plus/init.bash" ]; then
  . "$HOME/.config/wsl-plus/init.bash"
fi'
replace_managed_block "$BASH_RC" "$WSL_PLUS_BEGIN_MARKER" "$WSL_PLUS_END_MARKER" "$bash_block"

if [[ ${DEFAULTS[MANAGE_TMUX]} == 1 ]]; then
  # shellcheck disable=SC2016 # tmux expands HOME when it reads this block.
  tmux_block='if-shell "test \"${WSL_PLUS_DISABLE:-0}\" != 1 && test -r $HOME/.local/share/wsl-plus/current/core/tmux/tmux.conf" "source-file $HOME/.local/share/wsl-plus/current/core/tmux/tmux.conf"'
  if [[ ${DEFAULTS[ENABLE_LOCAL_SESSIONS]} == 1 ]]; then
    # shellcheck disable=SC2016
    tmux_block+=$'\n''if-shell "test \"${WSL_PLUS_DISABLE:-0}\" != 1 && test -r $HOME/.local/share/wsl-plus/current/core/tmux/local-sessions.conf" "source-file $HOME/.local/share/wsl-plus/current/core/tmux/local-sessions.conf"'
  fi
  if [[ ${DEFAULTS[ENABLE_LOCAL_SESSIONS]} == 1 && ${DEFAULTS[SESSION_BACKEND]} == auto ]]; then
    # shellcheck disable=SC2016
    tmux_block+=$'\n''if-shell "test \"${WSL_PLUS_DISABLE:-0}\" != 1 && test -r $HOME/.local/share/wsl-plus/current/core/tmux/home-sessions.conf" "source-file $HOME/.local/share/wsl-plus/current/core/tmux/home-sessions.conf"'
  fi
  replace_managed_block "$TMUX_RC" "$WSL_PLUS_TMUX_BEGIN_MARKER" "$WSL_PLUS_TMUX_END_MARKER" "$tmux_block"
fi

capture_protected_fingerprint "$protected_paths_file" "$plan_tmp/protected.after"
capture_shell_state "$plan_tmp/shell.enabled" "$protected_commands_file" 0
capture_shell_state "$plan_tmp/shell.disabled" "$protected_commands_file" 1

if ! cmp -s "$plan_tmp/protected.before" "$plan_tmp/protected.after"; then
  diff -u "$plan_tmp/protected.before" "$plan_tmp/protected.after" >&2 || true
  die 'An integration-protected path changed during installation.'
fi

if ! cmp -s "$plan_tmp/shell.causality-before" "$plan_tmp/shell.disabled"; then
  diff -u "$plan_tmp/shell.causality-before" "$plan_tmp/shell.disabled" >&2 || true
  die 'WSL Plus changed shell state even though WSL_PLUS_DISABLE=1.'
fi

if ! cmp -s "$plan_tmp/shell.disabled" "$plan_tmp/shell.enabled"; then
  diff -u "$plan_tmp/shell.disabled" "$plan_tmp/shell.enabled" >&2 || true
  die 'WSL Plus changed interactive-shell PATH or protected command resolution.'
fi

install_record="$STATE_ROOT/installations/$transaction_id.conf"
mkdir -p "$(dirname "$install_record")"
cat > "$install_record" <<EOF_RECORD
VERSION=$version
POLICY=$policy_id
INTEGRATION=$integration_id
MODE=$mode
PLAN_ID=$plan_id
BACKUP_DIR=$backup_dir
LEGACY_MACHINE_LOCK=$([[ -e $MACHINE_LOCK ]] && printf 'present' || printf 'absent')
INSTALLED_AT=$transaction_id
EOF_RECORD
ln -sfn "$install_record" "$STATE_ROOT/current-install.conf"

WSL_PLUS_ALLOW_NON_WSL=${WSL_PLUS_ALLOW_NON_WSL:-0} \
WSL_PLUS_ETC_ROOT=${WSL_PLUS_ETC_ROOT:-} \
  "$DATA_ROOT/current/doctor.sh"

transaction_active=0
rm -rf -- "$DATA_ROOT/current.previous"
log_info "Installed WSL Plus $version with policy=$policy_id integration=$integration_id mode=$mode"
