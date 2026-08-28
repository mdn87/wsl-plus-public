# shellcheck shell=bash

_wsl_plus_find_windows_exe() {
  local name=$1
  local candidate

  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi

  for candidate in \
    "/mnt/c/Windows/System32/$name" \
    "/mnt/c/Windows/$name"; do
    [[ -x $candidate ]] && {
      printf '%s\n' "$candidate"
      return 0
    }
  done

  return 1
}

wslp-open() {
  [[ ${WSL_PLUS_ALLOW_WINDOWS_APP_LAUNCH:-0} == 1 ]] || {
    printf 'Windows application launch is denied by the active policy.\n' >&2
    return 1
  }

  local explorer
  explorer=$(_wsl_plus_find_windows_exe explorer.exe) || {
    printf 'explorer.exe is unavailable. Windows interop may be disabled.\n' >&2
    return 1
  }

  local target=${1:-.}
  if command -v wslpath >/dev/null 2>&1; then
    target=$(wslpath -w "$target" 2>/dev/null || printf '%s' "$target")
  fi
  "$explorer" "$target"
}

wslp-clip-copy() {
  [[ ${WSL_PLUS_ALLOW_WINDOWS_CLIPBOARD:-0} == 1 ]] || {
    printf 'Windows clipboard access is denied by the active policy.\n' >&2
    return 1
  }

  local clip
  clip=$(_wsl_plus_find_windows_exe clip.exe) || {
    printf 'clip.exe is unavailable. Windows interop may be disabled.\n' >&2
    return 1
  }
  "$clip"
}

wslp-clip-paste() {
  [[ ${WSL_PLUS_ALLOW_WINDOWS_CLIPBOARD:-0} == 1 ]] || {
    printf 'Windows clipboard access is denied by the active policy.\n' >&2
    return 1
  }

  local powershell
  powershell=$(_wsl_plus_find_windows_exe powershell.exe) || {
    printf 'powershell.exe is unavailable. Windows interop may be disabled.\n' >&2
    return 1
  }
  "$powershell" -NoProfile -NonInteractive -Command Get-Clipboard | sed 's/\r$//'
}

wslp-cdrive() {
  [[ ${WSL_PLUS_ALLOW_CROSS_FILESYSTEM:-0} == 1 ]] || {
    printf 'Cross-filesystem access is denied by the active policy.\n' >&2
    return 1
  }

  local drive=${1:-c}
  local suffix=${2:-}
  drive=${drive,,}
  [[ $drive =~ ^[a-z]$ ]] || {
    printf 'usage: wslp-cdrive [DRIVE_LETTER] [RELATIVE_PATH]\n' >&2
    return 2
  }
  cd -- "/mnt/$drive/$suffix" || return
}
