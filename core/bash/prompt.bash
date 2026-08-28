# shellcheck shell=bash

_wsl_plus_git_branch() {
  command -v git >/dev/null 2>&1 || return 0
  local branch
  branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || return 0
  printf ' [%s]' "$branch"
}

# The prompt is intentionally plain Bash. It has no network calls and no
# package-manager dependency. Profiles that set MANAGE_PROMPT=0 never source
# this file, so an existing prompt is left untouched.
PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]$(_wsl_plus_git_branch)\n\$ '
