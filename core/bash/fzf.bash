# shellcheck shell=bash

command -v fzf >/dev/null 2>&1 || return 0

export FZF_DEFAULT_OPTS=${FZF_DEFAULT_OPTS:---height=45% --layout=reverse --border}

# ble.sh owns the interactive line editor when active. Its built-in history
# search and completion remain available; loading readline-oriented fzf shell
# bindings on top is unsupported by ble.sh upstream.
[[ -z ${BLE_VERSION-} ]] || return 0

# Distribution packages place Bash integration in different locations.
for _wsl_plus_fzf_file in \
  /usr/share/doc/fzf/examples/key-bindings.bash \
  /usr/share/fzf/key-bindings.bash \
  "$HOME/.fzf/shell/key-bindings.bash"; do
  if [[ -r $_wsl_plus_fzf_file ]]; then
    # shellcheck disable=SC1090
    . "$_wsl_plus_fzf_file"
    break
  fi
done

for _wsl_plus_fzf_file in \
  /usr/share/doc/fzf/examples/completion.bash \
  /usr/share/fzf/completion.bash \
  "$HOME/.fzf/shell/completion.bash"; do
  if [[ -r $_wsl_plus_fzf_file ]]; then
    # shellcheck disable=SC1090
    . "$_wsl_plus_fzf_file"
    break
  fi
done

unset _wsl_plus_fzf_file
