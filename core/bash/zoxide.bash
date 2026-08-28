# shellcheck shell=bash

command -v zoxide >/dev/null 2>&1 || return 0

# zoxide records local directory use. It does not widen Windows, credential,
# repository, or agent capabilities.
eval "$(zoxide init bash)"
