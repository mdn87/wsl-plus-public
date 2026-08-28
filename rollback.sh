#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/common.sh
. "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/config.sh
. "$ROOT_DIR/lib/config.sh"

usage() {
  cat <<'HELP'
usage: ./rollback.sh [OPTIONS]

Options:
  --remove-machine-lock  Also remove /etc/wsl-plus/machine-policy.conf.
                         This is never done implicitly.
  --purge                Remove WSL Plus user files instead of restoring the
                         most recent transaction backup.
  --help                 Show this help.

APT packages are intentionally left installed.
HELP
}

remove_machine_lock=0
purge=0
while (($#)); do
  case $1 in
    --remove-machine-lock)
      remove_machine_lock=1
      shift
      ;;
    --purge)
      purge=1
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

DATA_ROOT="$HOME/.local/share/wsl-plus"
CONFIG_ROOT="$HOME/.config/wsl-plus"
STATE_ROOT="$HOME/.local/state/wsl-plus"
BIN_PATH="$HOME/.local/bin/wsl-plus"
BASH_RC="$HOME/.bashrc"
TMUX_RC="$HOME/.tmux.conf"
record_path="$STATE_ROOT/current-install.conf"
backup_dir=

ssh_agent_command="$DATA_ROOT/current/bin/wsl-plus-ssh-agent"
if [[ -x $ssh_agent_command && -r $CONFIG_ROOT/runtime.conf ]]; then
  declare -A ACTIVE_RUNTIME=()
  if load_kv_config "$CONFIG_ROOT/runtime.conf" ACTIVE_RUNTIME \
    && [[ ${ACTIVE_RUNTIME[WSL_PLUS_ALLOW_SHARED_SSH_AGENT]-0} == 1 ]] \
    && [[ ${ACTIVE_RUNTIME[WSL_PLUS_ALLOW_WINDOWS_INTEROP]-0} == 1 ]] \
    && [[ ${ACTIVE_RUNTIME[WSL_PLUS_ALLOW_CROSS_FILESYSTEM]-0} == 1 ]]; then
    "$ssh_agent_command" stop >/dev/null || log_warn 'Could not stop the Windows SSH-agent relay during rollback.'
  fi
fi

if [[ -r $record_path ]]; then
  declare -A RECORD=()
  load_kv_config "$record_path" RECORD || die "Invalid installation record: $record_path"
  backup_dir=${RECORD[BACKUP_DIR]-}
fi

if [[ $purge == 0 && -n $backup_dir && -d $backup_dir ]]; then
  log_info "Restoring transaction backup: $backup_dir"
  restore_backup "$DATA_ROOT/current" "$backup_dir" data-current
  restore_backup "$CONFIG_ROOT" "$backup_dir" config-root
  restore_backup "$BIN_PATH" "$backup_dir" bin-wsl-plus
  restore_backup "$BASH_RC" "$backup_dir" bashrc
  restore_backup "$TMUX_RC" "$backup_dir" tmuxrc
else
  log_info 'Removing marker-bounded shell changes and user-level WSL Plus files.'
  remove_managed_block "$BASH_RC" "$WSL_PLUS_BEGIN_MARKER" "$WSL_PLUS_END_MARKER"
  remove_managed_block "$TMUX_RC" "$WSL_PLUS_TMUX_BEGIN_MARKER" "$WSL_PLUS_TMUX_END_MARKER"
  rm -rf -- "$DATA_ROOT/current" "$DATA_ROOT/current.previous" "$CONFIG_ROOT"
  rm -f -- "$BIN_PATH"
fi

rm -f -- "$record_path"

if [[ $remove_machine_lock == 1 ]]; then
  ETC_PREFIX=${WSL_PLUS_ETC_ROOT:-}
  machine_lock="$ETC_PREFIX/etc/wsl-plus/machine-policy.conf"
  if [[ -e $machine_lock ]]; then
    if [[ -n ${WSL_PLUS_ETC_ROOT-} || $(id -u) -eq 0 ]]; then
      rm -f -- "$machine_lock"
    else
      command_exists sudo || die "sudo is required to remove $machine_lock"
      sudo rm -f -- "$machine_lock"
    fi
    log_info "Removed machine policy lock: $machine_lock"
  fi
else
  log_info 'Machine policy lock retained.'
fi

log_info 'Rollback complete. Installed APT packages were not removed.'
