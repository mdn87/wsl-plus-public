# shellcheck shell=bash

# ble.sh requires an interactive terminal on all three standard streams. Skip
# installer probes and other interactive-but-nonterminal Bash processes.
[[ -t 0 && -t 1 && -t 2 ]] || return 0
[[ -z ${BLE_VERSION-} ]] || return 0

_wsl_plus_blesh_file=
for _wsl_plus_blesh_candidate in \
  "${XDG_DATA_HOME:-$HOME/.local/share}/blesh/ble.sh" \
  /usr/local/share/blesh/ble.sh \
  /usr/share/blesh/ble.sh; do
  if [[ -r $_wsl_plus_blesh_candidate ]]; then
    _wsl_plus_blesh_file=$_wsl_plus_blesh_candidate
    break
  fi
done

if [[ -n $_wsl_plus_blesh_file ]]; then
  # Use only the package-owned configuration. In particular, do not execute a
  # user-provided ~/.blerc implicitly as part of the managed startup block.
  # shellcheck disable=SC1090
  . "$_wsl_plus_blesh_file" --attach=none \
    --rcfile "$WSL_PLUS_ROOT/core/bash/blesh.rc"
  if declare -F ble-attach >/dev/null 2>&1; then
    ble-attach
  fi
fi

unset _wsl_plus_blesh_file _wsl_plus_blesh_candidate
