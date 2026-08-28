# shellcheck shell=bash

wsl_plus_attach_home_ssh_agent() {
  local state_dir socket_path pid_file pid result had_errexit=0
  [[ ${WSL_PLUS_ALLOW_SHARED_SSH_AGENT:-0} == 1 \
    && ${WSL_PLUS_ALLOW_WINDOWS_INTEROP:-0} == 1 \
    && ${WSL_PLUS_ALLOW_CROSS_FILESYSTEM:-0} == 1 ]] || return 0
  state_dir=$HOME/.local/state/wsl-plus/ssh-agent
  socket_path=$state_dir/agent.sock
  pid_file=$state_dir/relay.pid
  [[ -r $pid_file && -S $socket_path ]] || return 0
  IFS= read -r pid < "$pid_file"
  [[ $pid =~ ^[1-9][0-9]*$ && -r /proc/$pid/cmdline ]] || return 0
  tr '\0' ' ' < "/proc/$pid/cmdline" | grep -Fq -- "UNIX-LISTEN:$socket_path" || return 0
  command -v timeout >/dev/null 2>&1 || return 0
  command -v ssh-add >/dev/null 2>&1 || return 0
  [[ $- == *e* ]] && had_errexit=1
  set +e
  SSH_AUTH_SOCK=$socket_path timeout 1 ssh-add -l >/dev/null 2>&1
  result=$?
  ((had_errexit == 1)) && set -e
  if [[ $result == 0 || $result == 1 ]]; then
    export SSH_AUTH_SOCK=$socket_path
  fi
}

wsl_plus_attach_home_ssh_agent
unset -f wsl_plus_attach_home_ssh_agent
