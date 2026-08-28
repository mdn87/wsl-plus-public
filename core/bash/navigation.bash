# shellcheck shell=bash

wslp-mkcd() {
  [[ $# -eq 1 ]] || {
    printf 'usage: wslp-mkcd DIRECTORY\n' >&2
    return 2
  }
  mkdir -p -- "$1" && cd -- "$1" || return
}

wslp-up() {
  local count=${1:-1}
  local path='.'
  local i

  [[ $count =~ ^[0-9]+$ ]] || {
    printf 'usage: wslp-up [COUNT]\n' >&2
    return 2
  }

  for ((i = 0; i < count; i++)); do
    path+='/..'
  done
  cd -- "$path" || return
}

wslp-bat() {
  if command -v bat >/dev/null 2>&1; then
    command bat "$@"
  elif command -v batcat >/dev/null 2>&1; then
    command batcat "$@"
  else
    command cat "$@"
  fi
}

wslp-fd() {
  if command -v fd >/dev/null 2>&1; then
    command fd "$@"
  elif command -v fdfind >/dev/null 2>&1; then
    command fdfind "$@"
  else
    command find . -iname "${1:-*}"
  fi
}

wslp-extract() {
  [[ $# -eq 1 ]] || {
    printf 'usage: wslp-extract ARCHIVE\n' >&2
    return 2
  }

  local archive=$1
  [[ -f $archive ]] || {
    printf 'archive not found: %s\n' "$archive" >&2
    return 1
  }

  case $archive in
    *.tar.bz2|*.tbz2) tar -xjf "$archive" ;;
    *.tar.gz|*.tgz) tar -xzf "$archive" ;;
    *.tar.xz|*.txz) tar -xJf "$archive" ;;
    *.tar) tar -xf "$archive" ;;
    *.bz2) bunzip2 "$archive" ;;
    *.gz) gunzip "$archive" ;;
    *.xz) unxz "$archive" ;;
    *.zip) unzip "$archive" ;;
    *.7z) 7z x "$archive" ;;
    *)
      printf 'unsupported archive type: %s\n' "$archive" >&2
      return 2
      ;;
  esac
}

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
