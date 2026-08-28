#!/usr/bin/env bash

# shellcheck shell=bash

contract_validate_absolute_path() {
  local target=$1
  [[ $target == /* ]] || return 1
  [[ $target != / && $target != *'//'* && $target != */./* && $target != */../* ]]
}

contract_validate_effects() {
  local file=$1 line_no=0 effect target extra

  while IFS=$'\t' read -r effect target extra || [[ -n $effect || -n $target || -n $extra ]]; do
    line_no=$((line_no + 1))
    [[ -z $effect && -z $target && -z $extra ]] && continue
    [[ -n $effect && -n $target && -z $extra ]] || {
      log_error "Invalid protected effect at $file:$line_no"
      return 1
    }
    case $effect in
      FILE_NO_WRITE|AUTHORIZATION_LANE_NO_CHANGE)
        contract_validate_absolute_path "$target" || {
          log_error "Protected effect target is not a normalized absolute path at $file:$line_no"
          return 1
        }
        ;;
      COMMAND_RESOLUTION_NO_CHANGE)
        [[ $target =~ ^[a-zA-Z0-9._+-]+$ ]] || {
          log_error "Invalid protected command at $file:$line_no"
          return 1
        }
        ;;
      *)
        log_error "Unsupported protected effect $effect at $file:$line_no"
        return 1
        ;;
    esac
  done < "$file"
}

contract_validate_detection_facts() {
  local file=$1 line_no=0 fact target extra count=0

  while IFS=$'\t' read -r fact target extra || [[ -n $fact || -n $target || -n $extra ]]; do
    line_no=$((line_no + 1))
    [[ -z $fact && -z $target && -z $extra ]] && continue
    [[ -n $fact && -n $target && -z $extra ]] || {
      log_error "Invalid detection fact at $file:$line_no"
      return 1
    }
    case $fact in
      ROOT_REGULAR_FILE|ROOT_EXECUTABLE) ;;
      *)
        log_error "Unsupported detection fact $fact at $file:$line_no"
        return 1
        ;;
    esac
    contract_validate_absolute_path "$target" || {
      log_error "Detection target is not a normalized absolute path at $file:$line_no"
      return 1
    }
    count=$((count + 1))
  done < "$file"

  ((count > 0)) || {
    log_error "Detection facts are empty: $file"
    return 1
  }
}

contract_validate_checksum_manifest() {
  local contract_dir=$1 sums_file=$2 effects_name=$3 facts_name=$4
  local line line_no=0 hash filename count=0
  local -A expected=() seen=()

  expected[contract.conf]=$(sha256_file_or_absent "$contract_dir/contract.conf")
  expected[$effects_name]=$(sha256_file_or_absent "$contract_dir/$effects_name")
  expected[$facts_name]=$(sha256_file_or_absent "$contract_dir/$facts_name")

  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))
    line=${line%$'\r'}
    [[ $line =~ ^([0-9a-f]{64})[[:space:]][[:space:]]([a-zA-Z0-9._-]+)$ ]] || {
      log_error "Invalid contract checksum row at $sums_file:$line_no"
      return 1
    }
    hash=${BASH_REMATCH[1]}
    filename=${BASH_REMATCH[2]}
    [[ -v "expected[$filename]" && ! -v "seen[$filename]" ]] || {
      log_error "Unexpected or duplicate contract checksum target at $sums_file:$line_no"
      return 1
    }
    [[ $hash == "${expected[$filename]}" ]] || {
      log_error "Contract checksum does not match $filename"
      return 1
    }
    seen[$filename]=1
    count=$((count + 1))
  done < "$sums_file"

  ((count == 3)) || {
    log_error 'Contract checksum manifest must cover exactly contract.conf and both data files.'
    return 1
  }
}

load_integration_contract() {
  local contract_dir=$1 target_name=$2
  local metadata_file="$contract_dir/contract.conf"
  local sums_file="$contract_dir/SHA256SUMS"
  local effects_file facts_file expected index entry
  local -a contract_entries=() expected_entries=()
  local -n contract=$target_name

  [[ -d $contract_dir && ! -L $contract_dir ]] || {
    log_error "Integration contract directory is missing or is a symlink: $contract_dir"
    return 1
  }
  mapfile -t contract_entries < <(
    find "$contract_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort
  )
  expected_entries=(SHA256SUMS contract.conf detection-facts.tsv effects.tsv)
  [[ ${#contract_entries[@]} -eq ${#expected_entries[@]} ]] || {
    log_error "Integration contract directory has unexpected entries: $contract_dir"
    return 1
  }
  for index in "${!expected_entries[@]}"; do
    [[ ${contract_entries[$index]} == "${expected_entries[$index]}" ]] || {
      log_error "Integration contract directory has unexpected entries: $contract_dir"
      return 1
    }
  done
  for entry in "${expected_entries[@]}"; do
    [[ -f $contract_dir/$entry && ! -L $contract_dir/$entry \
      && -r $contract_dir/$entry ]] || {
      log_error "Integration contract entry is missing, unreadable, or a symlink: $contract_dir/$entry"
      return 1
    }
  done
  load_kv_config "$metadata_file" "$target_name" || return 1
  config_require_exact_keys "$target_name" \
    SCHEMA_VERSION CONTRACT_ID OWNER_REPOSITORY OWNER_COMMIT POLICY_COMMIT \
    EFFECTS_FILE EFFECTS_SHA256 DETECTION_FACTS_FILE \
    DETECTION_FACTS_SHA256 || return 1

  [[ ${contract[SCHEMA_VERSION]} == 1 ]] || {
    log_error "Unsupported integration contract schema: ${contract[SCHEMA_VERSION]}"
    return 1
  }
  # Contract IDs are owned by the site that publishes the contract. The loader
  # only requires a well-formed identifier; the selected integration decides
  # which contract it accepts.
  [[ ${contract[CONTRACT_ID]} =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || {
    log_error "Malformed integration contract ID: ${contract[CONTRACT_ID]}"
    return 1
  }
  [[ ${contract[OWNER_REPOSITORY]} =~ ^[a-zA-Z0-9._/-]+$ ]] || {
    log_error 'Integration contract owner repository is invalid.'
    return 1
  }
  [[ ${contract[OWNER_COMMIT]} =~ ^[0-9a-f]{40}$ ]] || {
    log_error 'Integration contract owner commit must be a lowercase 40-character object ID.'
    return 1
  }
  [[ ${contract[POLICY_COMMIT]} =~ ^[0-9a-f]{40}$ ]] || {
    log_error 'Integration contract policy commit must be a lowercase 40-character object ID.'
    return 1
  }
  [[ ${contract[EFFECTS_FILE]} =~ ^[a-zA-Z0-9._-]+$ \
    && ${contract[DETECTION_FACTS_FILE]} =~ ^[a-zA-Z0-9._-]+$ ]] || {
    log_error 'Integration contract data filenames must be local basenames.'
    return 1
  }
  [[ ${contract[EFFECTS_FILE]} == effects.tsv \
    && ${contract[DETECTION_FACTS_FILE]} == detection-facts.tsv ]] || {
    log_error 'Integration contract v1 requires effects.tsv and detection-facts.tsv.'
    return 1
  }
  [[ ${contract[EFFECTS_FILE]} != contract.conf \
    && ${contract[EFFECTS_FILE]} != SHA256SUMS \
    && ${contract[DETECTION_FACTS_FILE]} != contract.conf \
    && ${contract[DETECTION_FACTS_FILE]} != SHA256SUMS \
    && ${contract[EFFECTS_FILE]} != "${contract[DETECTION_FACTS_FILE]}" ]] || {
    log_error 'Integration contract data filenames must be distinct from metadata files.'
    return 1
  }
  [[ ${contract[EFFECTS_SHA256]} =~ ^[0-9a-f]{64}$ \
    && ${contract[DETECTION_FACTS_SHA256]} =~ ^[0-9a-f]{64}$ ]] || {
    log_error 'Integration contract hashes must be lowercase SHA-256 values.'
    return 1
  }

  effects_file="$contract_dir/${contract[EFFECTS_FILE]}"
  facts_file="$contract_dir/${contract[DETECTION_FACTS_FILE]}"
  [[ -f $metadata_file && ! -L $metadata_file && -r $metadata_file ]] || {
    log_error "Integration contract metadata is missing, unreadable, or a symlink: $metadata_file"
    return 1
  }
  [[ -f $effects_file && ! -L $effects_file && -r $effects_file ]] || {
    log_error "Integration contract effects file is missing or unreadable: $effects_file"
    return 1
  }
  [[ -f $facts_file && ! -L $facts_file && -r $facts_file ]] || {
    log_error "Integration contract detection facts are missing or unreadable: $facts_file"
    return 1
  }
  [[ -f $sums_file && ! -L $sums_file && -r $sums_file ]] || {
    log_error "Integration contract checksum file is missing or unreadable: $sums_file"
    return 1
  }

  expected=$(sha256_file_or_absent "$effects_file")
  [[ $expected == "${contract[EFFECTS_SHA256]}" ]] || {
    log_error 'Integration contract effects hash does not match metadata.'
    return 1
  }
  expected=$(sha256_file_or_absent "$facts_file")
  [[ $expected == "${contract[DETECTION_FACTS_SHA256]}" ]] || {
    log_error 'Integration contract detection hash does not match metadata.'
    return 1
  }
  contract_validate_checksum_manifest "$contract_dir" "$sums_file" \
    "${contract[EFFECTS_FILE]}" "${contract[DETECTION_FACTS_FILE]}" || return 1

  contract_validate_effects "$effects_file" || return 1
  contract_validate_detection_facts "$facts_file" || return 1
}

validate_installed_contract_layout() {
  local contract_dir=$1 expected_uid=${2:-$(id -u)} path mode uid
  local -a files=(contract.conf effects.tsv detection-facts.tsv SHA256SUMS)

  [[ -d $contract_dir && ! -L $contract_dir ]] || return 1
  mode=$(stat -c '%a' -- "$contract_dir" 2>/dev/null) || return 1
  uid=$(stat -c '%u' -- "$contract_dir" 2>/dev/null) || return 1
  [[ $mode == 755 && $uid == "$expected_uid" ]] || return 1

  for path in "${files[@]}"; do
    path="$contract_dir/$path"
    [[ -f $path && ! -L $path ]] || return 1
    mode=$(stat -c '%a' -- "$path" 2>/dev/null) || return 1
    uid=$(stat -c '%u' -- "$path" 2>/dev/null) || return 1
    [[ $mode == 644 && $uid == "$expected_uid" ]] || return 1
  done
}

validate_integration_contract_pin() {
  local integration_name=$1 contract_name=$2
  local -n integration=$integration_name
  local -n contract=$contract_name

  [[ ${contract[SCHEMA_VERSION]-} == "${integration[CONTRACT_SCHEMA_VERSION]-}" ]] || {
    log_error 'Integration and contract schema versions differ.'
    return 1
  }
  [[ ${contract[OWNER_COMMIT]-} == "${integration[CONTRACT_OWNER_COMMIT]-}" ]] || {
    log_error 'Integration and contract owner baselines differ.'
    return 1
  }
  [[ ${integration[CONTRACT_PUBLICATION_COMMIT]-} =~ ^[0-9a-f]{40}$ ]] || {
    log_error 'Integration contract publication commit must be a lowercase 40-character object ID.'
    return 1
  }
}

contract_materialize_effect_lists() {
  local contract_dir=$1 target_name=$2 paths_file=$3 commands_file=$4
  local -n contract=$target_name
  local effects_file="$contract_dir/${contract[EFFECTS_FILE]}"
  local effect target extra

  : > "$paths_file"
  : > "$commands_file"
  while IFS=$'\t' read -r effect target extra || [[ -n $effect || -n $target || -n $extra ]]; do
    case $effect in
      FILE_NO_WRITE|AUTHORIZATION_LANE_NO_CHANGE)
        grep -Fqx -- "$target" "$paths_file" 2>/dev/null || printf '%s\n' "$target" >> "$paths_file"
        ;;
      COMMAND_RESOLUTION_NO_CHANGE)
        grep -Fqx -- "$target" "$commands_file" 2>/dev/null || printf '%s\n' "$target" >> "$commands_file"
        ;;
    esac
  done < "$effects_file"
}

contract_detection_state() {
  local contract_dir=$1 target_name=$2 root_prefix=${3:-}
  local -n contract=$target_name
  local facts_file="$contract_dir/${contract[DETECTION_FACTS_FILE]}"
  local fact target extra resolved total=0 matched=0 observed=0

  while IFS=$'\t' read -r fact target extra || [[ -n $fact || -n $target || -n $extra ]]; do
    [[ -z $fact && -z $target && -z $extra ]] && continue
    total=$((total + 1))
    resolved="${root_prefix}${target}"
    [[ -e $resolved || -L $resolved ]] && observed=$((observed + 1))
    case $fact in
      ROOT_REGULAR_FILE) [[ -f $resolved ]] && matched=$((matched + 1)) ;;
      ROOT_EXECUTABLE) [[ -f $resolved && -x $resolved ]] && matched=$((matched + 1)) ;;
    esac
  done < "$facts_file"

  if ((matched == total)); then
    printf 'present'
  elif ((observed == 0)); then
    printf 'absent'
  else
    printf 'partial'
  fi
}
