#!/usr/bin/env bash

# shellcheck shell=bash
# Namerefs intentionally point at associative arrays supplied by callers.
# shellcheck disable=SC2178

load_kv_config() {
  local file=$1
  local target_name=$2
  local line key value line_no=0

  [[ -r $file ]] || {
    printf 'Configuration file is not readable: %s\n' "$file" >&2
    return 1
  }

  local -n target=$target_name
  target=()

  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))
    line=${line%$'\r'}

    [[ $line =~ ^[[:space:]]*$ ]] && continue
    [[ $line =~ ^[[:space:]]*# ]] && continue

    if [[ ! $line =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
      printf 'Invalid configuration syntax at %s:%d\n' "$file" "$line_no" >&2
      return 1
    fi

    key=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}

    if [[ -v "target[$key]" ]]; then
      printf 'Duplicate configuration key %s at %s:%d\n' "$key" "$file" "$line_no" >&2
      return 1
    fi

    if [[ $value == *$'\n'* || $value == *$'\r'* ]]; then
      printf 'Configuration value for %s contains a newline\n' "$key" >&2
      return 1
    fi

    # target is an associative array; this subscript is not arithmetic.
    # shellcheck disable=SC2004
    target[$key]=$value
  done < "$file"
}

config_require_keys() {
  local target_name=$1
  shift
  local -n target=$target_name
  local key

  for key in "$@"; do
    if [[ ! -v "target[$key]" ]]; then
      printf 'Required configuration key is missing: %s\n' "$key" >&2
      return 1
    fi
  done
}

config_require_exact_keys() {
  local target_name=$1
  shift
  local -n target=$target_name
  local -A expected=()
  local key

  for key in "$@"; do
    expected[$key]=1
  done
  config_require_keys "$target_name" "$@" || return 1
  for key in "${!target[@]}"; do
    if [[ ! -v "expected[$key]" ]]; then
      printf 'Unsupported configuration key: %s\n' "$key" >&2
      return 1
    fi
  done
}

config_get() {
  local target_name=$1
  local key=$2
  local default_value=${3-}
  local -n target=$target_name

  if [[ -v "target[$key]" ]]; then
    printf '%s' "${target[$key]}"
  else
    printf '%s' "$default_value"
  fi
}

config_bool() {
  local target_name=$1
  local key=$2
  local -n target=$target_name
  local value=${target[$key]-}

  case $value in
    0|1)
      printf '%s' "$value"
      ;;
    *)
      printf 'Configuration key %s must be 0 or 1, got: %s\n' "$key" "$value" >&2
      return 1
      ;;
  esac
}
