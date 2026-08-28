# shellcheck shell=bash

shopt -s histappend

: "${HISTCONTROL:=ignoreboth:erasedups}"
: "${HISTSIZE:=50000}"
: "${HISTFILESIZE:=100000}"

export HISTCONTROL HISTSIZE HISTFILESIZE

# Live cross-session history merging is local shell behavior. Policy controls
# whether the additive PROMPT_COMMAND entry is enabled.
if [[ ${WSL_PLUS_ENABLE_HISTORY_PROMPT_HOOK:-0} == 1 ]]; then
  _wsl_plus_history_sync='history -a; history -n'

  if [[ -z ${PROMPT_COMMAND-} ]]; then
    PROMPT_COMMAND=$_wsl_plus_history_sync
  elif [[ $PROMPT_COMMAND != *"$_wsl_plus_history_sync"* ]]; then
    PROMPT_COMMAND="$_wsl_plus_history_sync; $PROMPT_COMMAND"
  fi

  unset _wsl_plus_history_sync
fi
