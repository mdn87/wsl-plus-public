# shellcheck shell=bash

wslp-session() {
  "${WSL_PLUS_ROOT:-$HOME/.local/share/wsl-plus/current}/bin/wsl-plus" session "$@"
}
