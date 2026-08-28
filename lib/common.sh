#!/usr/bin/env bash

# shellcheck shell=bash

# These constants are consumed by scripts that source this library.
# shellcheck disable=SC2034
WSL_PLUS_BEGIN_MARKER='# >>> wsl-plus managed block >>>'
# shellcheck disable=SC2034
WSL_PLUS_END_MARKER='# <<< wsl-plus managed block <<<'
# shellcheck disable=SC2034
WSL_PLUS_TMUX_BEGIN_MARKER='# >>> wsl-plus tmux block >>>'
# shellcheck disable=SC2034
WSL_PLUS_TMUX_END_MARKER='# <<< wsl-plus tmux block <<<'

log_info() {
  printf '[wsl-plus] %s\n' "$*"
}

log_warn() {
  printf '[wsl-plus] WARNING: %s\n' "$*" >&2
}

log_error() {
  printf '[wsl-plus] ERROR: %s\n' "$*" >&2
}

die() {
  log_error "$*"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

windows_mount_targets() {
  local mountinfo=${WSL_PLUS_MOUNTINFO_FILE:-}
  local target
  if [[ -z $mountinfo ]]; then
    if [[ -n ${WSL_PLUS_ETC_ROOT:-} ]]; then
      mountinfo=$WSL_PLUS_ETC_ROOT/proc/self/mountinfo
    else
      mountinfo=/proc/self/mountinfo
    fi
  fi
  [[ -r $mountinfo ]] || return 0
  while IFS= read -r target; do
    target=${target//\\040/ }
    target=${target//\\011/$'\t'}
    target=${target//\\134/\\}
    [[ $target =~ ^/mnt/[^/]+$ ]] && printf '%s\n' "$target"
  done < <(awk '
    {
      separator = 0
      for (field = 1; field <= NF; field++) {
        if ($field == "-") {
          separator = field
          break
        }
      }
      if (separator == 0 || $5 !~ "^/mnt/[^/]+$") {
        next
      }
      filesystem = $(separator + 1)
      mount_source = $(separator + 2)
      if (filesystem == "drvfs" || mount_source ~ "^[A-Za-z]:" || $0 ~ "aname=drvfs") {
        print $5
      }
    }
  ' "$mountinfo")
}

windows_executable_targets() {
  local command_name
  for command_name in powershell.exe cmd.exe explorer.exe wscript.exe cscript.exe; do
    command -v "$command_name" 2>/dev/null || true
  done
}

is_wsl() {
  [[ -n ${WSL_DISTRO_NAME-} ]] || grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null
}

sha256_text() {
  if command_exists sha256sum; then
    sha256sum | awk '{print $1}'
  elif command_exists shasum; then
    shasum -a 256 | awk '{print $1}'
  else
    return 127
  fi
}

sha256_file_or_absent() {
  local file=$1
  if [[ -f $file ]]; then
    if command_exists sha256sum; then
      sha256sum "$file" | awk '{print $1}'
    else
      shasum -a 256 "$file" | awk '{print $1}'
    fi
  elif [[ -e $file ]]; then
    printf '<not-a-regular-file>'
  else
    printf '<absent>'
  fi
}

expand_path_token() {
  local raw=$1
  # shellcheck disable=SC2016 # Match the literal tokens before expanding them.
  raw=${raw//'${HOME}'/$HOME}
  # shellcheck disable=SC2016
  raw=${raw//'$HOME'/$HOME}
  raw=${raw/#\~/$HOME}
  printf '%s' "$raw"
}

canonicalize_lexical_path() {
  local path=$1

  if command_exists realpath; then
    realpath -m -- "$path"
  else
    python3 - "$path" <<'PY'
import os
import sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
  fi
}

path_is_within() {
  local candidate root
  candidate=$(canonicalize_lexical_path "$1")
  root=$(canonicalize_lexical_path "$2")
  [[ $candidate == "$root" || $candidate == "$root"/* ]]
}

assert_single_or_no_marker_block() {
  local file=$1
  local begin=$2
  local end=$3
  local begin_count=0 end_count=0

  [[ -e $file ]] || return 0
  [[ -f $file ]] || {
    log_error "Expected a regular file: $file"
    return 1
  }

  begin_count=$(grep -Fxc "$begin" "$file" 2>/dev/null || true)
  end_count=$(grep -Fxc "$end" "$file" 2>/dev/null || true)

  if (( begin_count > 1 || end_count > 1 || begin_count != end_count )); then
    log_error "Malformed managed block markers in $file"
    return 1
  fi
}

replace_managed_block() {
  local file=$1
  local begin=$2
  local end=$3
  local body=$4
  local tmp

  assert_single_or_no_marker_block "$file" "$begin" "$end" || return 1
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp=$(mktemp "${file}.wsl-plus.XXXXXX")

  awk -v begin="$begin" -v end="$end" '
    $0 == begin {inside=1; next}
    $0 == end {inside=0; next}
    !inside {print}
  ' "$file" > "$tmp"

  while [[ -s $tmp ]] && [[ $(tail -c 1 "$tmp" | wc -l) -eq 0 ]]; do
    printf '\n' >> "$tmp"
  done

  if [[ -s $tmp ]] && [[ $(tail -n 1 "$tmp") != '' ]]; then
    printf '\n' >> "$tmp"
  fi

  {
    printf '%s\n' "$begin"
    printf '%s\n' "$body"
    printf '%s\n' "$end"
  } >> "$tmp"

  chmod --reference="$file" "$tmp" 2>/dev/null || true
  mv -- "$tmp" "$file"
}

remove_managed_block() {
  local file=$1
  local begin=$2
  local end=$3
  local tmp

  [[ -e $file ]] || return 0
  assert_single_or_no_marker_block "$file" "$begin" "$end" || return 1
  tmp=$(mktemp "${file}.wsl-plus.XXXXXX")

  awk -v begin="$begin" -v end="$end" '
    $0 == begin {inside=1; next}
    $0 == end {inside=0; next}
    !inside {print}
  ' "$file" > "$tmp"

  chmod --reference="$file" "$tmp" 2>/dev/null || true
  mv -- "$tmp" "$file"
}

backup_if_present() {
  local source=$1
  local backup_dir=$2
  local label=$3

  mkdir -p "$backup_dir"
  if [[ -e $source ]]; then
    cp -a -- "$source" "$backup_dir/$label"
    printf 'present' > "$backup_dir/$label.state"
  else
    printf 'absent' > "$backup_dir/$label.state"
  fi
}

restore_backup() {
  local destination=$1
  local backup_dir=$2
  local label=$3
  local state_file="$backup_dir/$label.state"

  [[ -r $state_file ]] || return 0
  case $(cat "$state_file") in
    present)
      rm -rf -- "$destination"
      cp -a -- "$backup_dir/$label" "$destination"
      ;;
    absent)
      rm -rf -- "$destination"
      ;;
  esac
}

read_list_file() {
  local file=$1
  local target_name=$2
  local line
  local -n target=$target_name
  target=()

  [[ -r $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*$ ]] && continue
    [[ $line =~ ^[[:space:]]*# ]] && continue
    target+=("$line")
  done < "$file"
}

capture_command_fingerprint() {
  local commands_file=$1
  local output_file=$2
  local -a commands=()
  local command_name

  read_list_file "$commands_file" commands
  : > "$output_file"
  for command_name in "${commands[@]}"; do
    {
      printf 'COMMAND=%s\n' "$command_name"
      type -a -- "$command_name" 2>&1 || printf '<absent>\n'
      printf 'END_COMMAND\n'
    } >> "$output_file"
  done
}

capture_protected_fingerprint() {
  local paths_file=$1
  local output_file=$2
  local -a paths=()
  local raw path

  read_list_file "$paths_file" paths
  : > "$output_file"

  for raw in "${paths[@]}"; do
    path=$(expand_path_token "$raw")
    printf 'PATH=%s\n' "$path" >> "$output_file"

    if [[ -L $path ]]; then
      printf 'TYPE=symlink TARGET=%s\n' "$(readlink -- "$path")" >> "$output_file"
      stat -c 'STAT=%f:%u:%g:%d:%i' -- "$path" >> "$output_file" 2>/dev/null || printf 'STAT=<unreadable>\n' >> "$output_file"
    elif [[ -f $path ]]; then
      if [[ -r $path ]]; then
        printf 'TYPE=file SHA256=%s\n' "$(sha256_file_or_absent "$path")" >> "$output_file"
      else
        printf 'TYPE=file SHA256=<unreadable>\n' >> "$output_file"
      fi
      stat -c 'STAT=%f:%u:%g:%d:%i' -- "$path" >> "$output_file" 2>/dev/null || printf 'STAT=<unreadable>\n' >> "$output_file"
    elif [[ -d $path ]]; then
      printf 'TYPE=directory\n' >> "$output_file"
      # Directory contents may be live service state. Preserve the root object
      # identity and ownership without treating legitimate child churn as an
      # installer mutation.
      stat -c 'STAT=%f:%u:%g:%d:%i' -- "$path" >> "$output_file" 2>/dev/null || printf 'STAT=<unreadable>\n' >> "$output_file"
    elif [[ -e $path ]]; then
      printf 'TYPE=other\n' >> "$output_file"
      stat -c 'STAT=%f:%u:%g:%d:%i' -- "$path" >> "$output_file" 2>/dev/null || printf 'STAT=<unreadable>\n' >> "$output_file"
    else
      printf 'TYPE=absent\n' >> "$output_file"
    fi
  done
}

capture_shell_state() {
  local output_file=$1
  local commands_file=$2
  local disable=${3:-0}
  local helper
  helper=$(mktemp)

  cat > "$helper" <<'BASH'
printf '__WSL_PLUS_STATE_BEGIN__\n'
printf 'PATH=%s\n' "$PATH"
while IFS= read -r command_name || [[ -n $command_name ]]; do
  [[ $command_name =~ ^[[:space:]]*$ ]] && continue
  [[ $command_name =~ ^[[:space:]]*# ]] && continue
  printf 'COMMAND=%s\n' "$command_name"
  type -a -- "$command_name" 2>&1 || printf '<absent>\n'
  printf 'END_COMMAND\n'
done < "$WSL_PLUS_COMMANDS_FILE"
printf '__WSL_PLUS_STATE_END__\n'
BASH

  local raw_output
  raw_output=$(mktemp)
  WSL_PLUS_DISABLE=$disable WSL_PLUS_COMMANDS_FILE=$commands_file bash -ic "source '$helper'" > "$raw_output" 2>&1 || {
    rm -f -- "$helper" "$raw_output"
    return 1
  }

  sed -n '/^__WSL_PLUS_STATE_BEGIN__$/,/^__WSL_PLUS_STATE_END__$/p' "$raw_output" \
    | sed '1d;$d' > "$output_file"

  rm -f -- "$helper" "$raw_output"
  [[ -s $output_file ]]
}

write_root_owned_file() {
  local destination=$1
  local mode=$2
  local content=$3
  local directory
  directory=$(dirname "$destination")

  if [[ -n ${WSL_PLUS_ETC_ROOT-} ]]; then
    mkdir -p "$directory"
    printf '%s\n' "$content" > "$destination"
    chmod "$mode" "$destination"
    return 0
  fi

  command_exists sudo || {
    log_error "sudo is required to write $destination"
    return 1
  }

  local temp_file
  temp_file=$(mktemp)
  printf '%s\n' "$content" > "$temp_file"
  sudo install -D -m "$mode" "$temp_file" "$destination"
  rm -f -- "$temp_file"
}
