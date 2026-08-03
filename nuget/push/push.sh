#!/usr/bin/env bash
set -euo pipefail

umask 077

SCRIPT_NAME="${0##*/}"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_NAME SCRIPT_DIR
readonly DEFAULT_ENV_FILE="$SCRIPT_DIR/.env"

ENV_FILE="${NUGET_ENV_FILE:-$DEFAULT_ENV_FILE}"
TEMP_FILE=""
TRIMMED_VALUE=""
PARSED_VALUE=""
SELECTED_PROFILE_ID=""
ACTION=""

PROFILE_IDS=()
PROFILE_NAMES=()
PROFILE_PACKAGE_IDS=()
PROFILE_DIRECTORIES=()
PROFILE_SOURCES=()
PROFILE_API_KEYS=()
PROFILE_SKIP_DUPLICATES=()

die() {
  printf '%s: error: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

usage_error() {
  usage >&2
  exit 2
}

cleanup() {
  if [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]]; then
    rm -f -- "$TEMP_FILE"
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [--profile PROFILE] [--version VERSION] [--env FILE] [--dry-run] [VERSION]
  $SCRIPT_NAME --add [--env FILE]
  $SCRIPT_NAME --remove [--profile PROFILE] [--env FILE]
  $SCRIPT_NAME --list [--env FILE]

With no arguments in a terminal, an interactive action menu is shown. A push can
also be run without prompts by providing both --profile and --version.

Options:
  -p, --profile PROFILE   Profile ID from the dotenv file
  -V, --version VERSION   NuGet package version to push
  -e, --env FILE          Dotenv file (default: $DEFAULT_ENV_FILE)
      --add               Interactively append a profile to the dotenv file
      --remove            Remove a profile (interactive unless --profile is set)
      --list              List configured profiles without exposing API keys
  -n, --dry-run           Print the resolved push target without running dotnet
  -h, --help              Show this help

For CI, NUGET_ENV_FILE may set the dotenv path and NUGET_API_KEY may override the
selected profile's API key. Bash 3.2 or newer is required.
EOF
}

require_option_value() {
  local option="$1"
  local value="${2-}"

  [[ -n "$value" ]] || {
    printf '%s: option requires a value: %s\n' "$SCRIPT_NAME" "$option" >&2
    usage_error
  }
}

normalize_profile_id() {
  local value="$1"

  [[ "$value" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || return 1
  printf '%s' "$value" | tr '[:lower:]-' '[:upper:]_'
}

trim_value() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  TRIMMED_VALUE="$value"
}

decode_dotenv_value() {
  local raw="$1"
  local value=""
  local char=""
  local next=""
  local backslash=$'\\'
  local i=0

  trim_value "$raw"
  raw="$TRIMMED_VALUE"

  if [[ "$raw" == \"* ]]; then
    (( ${#raw} >= 2 )) || die "invalid double-quoted value in $ENV_FILE"
    [[ "${raw: -1}" == '"' ]] || die "unterminated double-quoted value in $ENV_FILE"
    raw="${raw:1:${#raw}-2}"

    while (( i < ${#raw} )); do
      char="${raw:i:1}"
      if [[ "$char" == "$backslash" ]]; then
        (( i += 1 ))
        (( i < ${#raw} )) || die "trailing backslash in quoted value in $ENV_FILE"
        next="${raw:i:1}"
        case "$next" in
          n) value+=$'\n' ;;
          r) value+=$'\r' ;;
          t) value+=$'\t' ;;
          '"') value+='"' ;;
          "$backslash") value+="$backslash" ;;
          *) value+="$backslash$next" ;;
        esac
      else
        value+="$char"
      fi
      (( i += 1 ))
    done
  elif [[ "$raw" == \'* ]]; then
    (( ${#raw} >= 2 )) || die "invalid single-quoted value in $ENV_FILE"
    [[ "${raw: -1}" == "'" ]] || die "unterminated single-quoted value in $ENV_FILE"
    value="${raw:1:${#raw}-2}"
  else
    value="$raw"
  fi

  PARSED_VALUE="$value"
}

profile_index() {
  local wanted="$1"
  local i=0

  for (( i=0; i<${#PROFILE_IDS[@]}; i++ )); do
    if [[ "${PROFILE_IDS[$i]}" == "$wanted" ]]; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

set_profile_field() {
  local id="$1"
  local field="$2"
  local value="$3"
  local index=0

  if index=$(profile_index "$id"); then
    :
  else
    index=${#PROFILE_IDS[@]}
    PROFILE_IDS[index]="$id"
    PROFILE_NAMES[index]=""
    PROFILE_PACKAGE_IDS[index]=""
    PROFILE_DIRECTORIES[index]=""
    PROFILE_SOURCES[index]=""
    PROFILE_API_KEYS[index]=""
    PROFILE_SKIP_DUPLICATES[index]=""
  fi

  case "$field" in
    NAME) PROFILE_NAMES[index]="$value" ;;
    PACKAGE_ID) PROFILE_PACKAGE_IDS[index]="$value" ;;
    DIRECTORY) PROFILE_DIRECTORIES[index]="$value" ;;
    SOURCE) PROFILE_SOURCES[index]="$value" ;;
    API_KEY) PROFILE_API_KEYS[index]="$value" ;;
    SKIP_DUPLICATE) PROFILE_SKIP_DUPLICATES[index]="$value" ;;
  esac
}

load_profiles() {
  local line=""
  local key=""
  local raw_value=""
  local id=""
  local field=""

  [[ -f "$ENV_FILE" ]] || die "dotenv file not found: $ENV_FILE (use --add to create it)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
      key="${BASH_REMATCH[2]}"
      raw_value="${BASH_REMATCH[3]}"
    else
      die "invalid dotenv assignment: $line"
    fi

    if [[ "$key" =~ ^NUGET_PROFILE_([A-Z][A-Z0-9_]*)_(NAME|PACKAGE_ID|DIRECTORY|SOURCE|API_KEY|SKIP_DUPLICATE)$ ]]; then
      id="${BASH_REMATCH[1]}"
      field="${BASH_REMATCH[2]}"
      decode_dotenv_value "$raw_value"
      set_profile_field "$id" "$field" "$PARSED_VALUE"
    fi
  done < "$ENV_FILE"
}

validate_profile() {
  local index="$1"
  local id="${PROFILE_IDS[$index]}"
  local skip_duplicate="${PROFILE_SKIP_DUPLICATES[$index]}"

  [[ -n "${PROFILE_NAMES[$index]}" ]] || die "profile $id is missing NAME"
  [[ -n "${PROFILE_PACKAGE_IDS[$index]}" ]] || die "profile $id is missing PACKAGE_ID"
  [[ -n "${PROFILE_DIRECTORIES[$index]}" ]] || die "profile $id is missing DIRECTORY"
  [[ -n "${PROFILE_SOURCES[$index]}" ]] || die "profile $id is missing SOURCE"
  [[ "$skip_duplicate" == "true" || "$skip_duplicate" == "false" ]] || \
    die "profile $id has invalid SKIP_DUPLICATE (expected true or false)"
}

list_profiles() {
  local i=0

  (( ${#PROFILE_IDS[@]} > 0 )) || die "no profiles found in $ENV_FILE"
  for (( i=0; i<${#PROFILE_IDS[@]}; i++ )); do
    printf '%-16s %s\n' "${PROFILE_IDS[$i]}" "${PROFILE_NAMES[$i]:-(unnamed)}"
  done
}

require_terminal() {
  [[ -t 0 ]] || die "$1 requires an interactive terminal"
}

choose_profile() {
  local prompt="$1"
  local choice=""
  local i=0

  require_terminal "$prompt"
  (( ${#PROFILE_IDS[@]} > 0 )) || die "no profiles found in $ENV_FILE"

  printf '%s\n' "$prompt"
  for (( i=0; i<${#PROFILE_IDS[@]}; i++ )); do
    printf '  %d) %s (%s)\n' "$(( i + 1 ))" "${PROFILE_NAMES[$i]:-(unnamed)}" "${PROFILE_IDS[$i]}"
  done

  while true; do
    read -r -p "> " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#PROFILE_IDS[@]} )); then
      SELECTED_PROFILE_ID="${PROFILE_IDS[$(( choice - 1 ))]}"
      return 0
    fi
    printf 'Enter a number from 1 to %d.\n' "${#PROFILE_IDS[@]}" >&2
  done
}

prompt_with_default() {
  local prompt="$1"
  local default_value="$2"
  local input=""

  read -r -p "$prompt [$default_value]: " input
  printf '%s' "${input:-$default_value}"
}

dotenv_quote() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s"' "$value"
}

append_assignment() {
  local key="$1"
  local value="$2"

  {
    printf '%s=' "$key"
    dotenv_quote "$value"
    printf '\n'
  } >> "$ENV_FILE"
}

add_profile() {
  local raw_id=""
  local id=""
  local name=""
  local package_id=""
  local directory=""
  local source=""
  local api_key=""
  local skip_answer=""
  local skip_duplicate="false"
  local env_directory=""

  require_terminal "--add"
  if [[ -f "$ENV_FILE" ]]; then
    load_profiles
  fi

  read -r -p "Profile ID (letters, digits, '-' or '_'): " raw_id
  id=$(normalize_profile_id "$raw_id") || die "invalid profile ID: $raw_id"
  if profile_index "$id" &>/dev/null; then
    die "profile already exists: $id"
  fi

  name=$(prompt_with_default "Display name" "$raw_id")
  read -r -p "Package ID: " package_id
  [[ "$package_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid package ID: $package_id"
  directory=$(prompt_with_default "Package directory" ".")
  source=$(prompt_with_default "NuGet source" "https://api.nuget.org/v3/index.json")
  read -r -s -p "API key: " api_key
  printf '\n'
  [[ -n "$api_key" ]] || die "API key must not be empty"
  read -r -p "Skip duplicate packages? [y/N]: " skip_answer
  if [[ "$skip_answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    skip_duplicate="true"
  fi

  env_directory=$(dirname -- "$ENV_FILE")
  [[ -d "$env_directory" ]] || die "dotenv directory not found: $env_directory"
  printf '\n# BEGIN NUGET PROFILE %s\n' "$id" >> "$ENV_FILE"
  append_assignment "NUGET_PROFILE_${id}_NAME" "$name"
  append_assignment "NUGET_PROFILE_${id}_PACKAGE_ID" "$package_id"
  append_assignment "NUGET_PROFILE_${id}_DIRECTORY" "$directory"
  append_assignment "NUGET_PROFILE_${id}_SOURCE" "$source"
  append_assignment "NUGET_PROFILE_${id}_API_KEY" "$api_key"
  append_assignment "NUGET_PROFILE_${id}_SKIP_DUPLICATE" "$skip_duplicate"
  printf '# END NUGET PROFILE %s\n' "$id" >> "$ENV_FILE"
  chmod 600 "$ENV_FILE" || die "could not restrict permissions on $ENV_FILE"

  printf 'Added profile %s to %s.\n' "$id" "$ENV_FILE"
}

remove_profile() {
  local requested_id="$1"
  local id=""
  local index=0
  local confirmation=""
  local line=""
  local in_block=0
  local env_directory=""

  load_profiles
  if [[ -n "$requested_id" ]]; then
    id=$(normalize_profile_id "$requested_id") || die "invalid profile ID: $requested_id"
  else
    choose_profile "Select a profile to remove:"
    id="$SELECTED_PROFILE_ID"
  fi

  index=$(profile_index "$id") || die "unknown profile: $requested_id"
  if [[ -t 0 && -z "$requested_id" ]]; then
    read -r -p "Remove ${PROFILE_NAMES[$index]} ($id)? [y/N]: " confirmation
    [[ "$confirmation" =~ ^[Yy]([Ee][Ss])?$ ]] || {
      printf 'No profile removed.\n'
      return 0
    }
  fi

  env_directory=$(dirname -- "$ENV_FILE")
  TEMP_FILE=$(mktemp "$env_directory/.push.env.XXXXXX")

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == "# BEGIN NUGET PROFILE $id" ]]; then
      in_block=1
      continue
    fi
    if (( in_block )); then
      if [[ "$line" == "# END NUGET PROFILE $id" ]]; then
        in_block=0
      fi
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?NUGET_PROFILE_${id}_(NAME|PACKAGE_ID|DIRECTORY|SOURCE|API_KEY|SKIP_DUPLICATE)[[:space:]]*= ]]; then
      continue
    fi
    printf '%s\n' "$line" >> "$TEMP_FILE"
  done < "$ENV_FILE"

  (( in_block == 0 )) || die "unterminated profile block for $id in $ENV_FILE"
  chmod 600 "$TEMP_FILE" || die "could not restrict permissions on temporary dotenv file"
  mv -- "$TEMP_FILE" "$ENV_FILE"
  TEMP_FILE=""
  printf 'Removed profile %s from %s.\n' "$id" "$ENV_FILE"
}

expand_directory() {
  local directory="$1"
  local tilde='~'

  if [[ "$directory" == "$tilde" ]]; then
    printf '%s' "${HOME:?HOME must be set to expand ~ in a profile directory}"
  elif [[ "$directory" == "$tilde/"* ]]; then
    printf '%s/%s' "${HOME:?HOME must be set to expand ~ in a profile directory}" "${directory:2}"
  else
    printf '%s' "$directory"
  fi
}

push_package() {
  local requested_id="$1"
  local version="$2"
  local dry_run="$3"
  local id=""
  local index=0
  local directory=""
  local package_path=""
  local api_key=""
  local -a dotnet_args=()

  load_profiles
  if [[ -n "$requested_id" ]]; then
    id=$(normalize_profile_id "$requested_id") || die "invalid profile ID: $requested_id"
  else
    choose_profile "Select a profile to push:"
    id="$SELECTED_PROFILE_ID"
  fi

  index=$(profile_index "$id") || die "unknown profile: $requested_id"
  validate_profile "$index"

  if [[ -z "$version" ]]; then
    require_terminal "version selection"
    read -r -p "Package version: " version
  fi
  [[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]] || die "invalid package version: $version"

  directory=$(expand_directory "${PROFILE_DIRECTORIES[$index]}")
  package_path="$directory/${PROFILE_PACKAGE_IDS[$index]}.$version.nupkg"
  api_key="${NUGET_API_KEY:-${PROFILE_API_KEYS[$index]}}"
  [[ -n "$api_key" ]] || die "profile $id has no API key and NUGET_API_KEY is not set"

  printf 'Profile: %s\nPackage: %s\nSource:  %s\n' \
    "${PROFILE_NAMES[$index]} ($id)" "$package_path" "${PROFILE_SOURCES[$index]}"
  if (( dry_run )); then
    printf 'Dry run: dotnet was not invoked.\n'
    return 0
  fi

  [[ -f "$package_path" ]] || die "package not found: $package_path"
  command -v dotnet &>/dev/null || die "dotnet is not installed or not on PATH"

  dotnet_args=(nuget push "$package_path" --api-key "$api_key" --source "${PROFILE_SOURCES[$index]}")
  if [[ "${PROFILE_SKIP_DUPLICATES[$index]}" == "true" ]]; then
    dotnet_args+=(--skip-duplicate)
  fi
  dotnet "${dotnet_args[@]}"
}

interactive_action() {
  local choice=""

  require_terminal "the action menu"
  cat <<'EOF'
Choose an action:
  1) Push a package
  2) Add a profile
  3) Remove a profile
  4) List profiles
EOF
  while true; do
    read -r -p "> " choice
    case "$choice" in
      1) ACTION="push"; return 0 ;;
      2) ACTION="add"; return 0 ;;
      3) ACTION="remove"; return 0 ;;
      4) ACTION="list"; return 0 ;;
      *) printf 'Enter a number from 1 to 4.\n' >&2 ;;
    esac
  done
}

main() {
  local action="push"
  local action_was_set=0
  local profile=""
  local version=""
  local version_was_set=0
  local dry_run=0
  local positional_count=0

  if (( $# == 0 )) && [[ -t 0 ]]; then
    ACTION=""
    interactive_action
    action="$ACTION"
  fi

  while (( $# > 0 )); do
    case "$1" in
      -p|--profile)
        require_option_value "$1" "${2-}"
        profile="$2"
        shift 2
        ;;
      -V|--version)
        require_option_value "$1" "${2-}"
        (( version_was_set == 0 )) || usage_error
        version="$2"
        version_was_set=1
        shift 2
        ;;
      -e|--env)
        require_option_value "$1" "${2-}"
        ENV_FILE="$2"
        shift 2
        ;;
      --add|--remove|--list)
        (( action_was_set == 0 )) || usage_error
        action="${1#--}"
        action_was_set=1
        shift
        ;;
      -n|--dry-run)
        dry_run=1
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      --)
        shift
        (( $# <= 1 )) || usage_error
        if (( $# == 1 )); then
          (( version_was_set == 0 )) || usage_error
          version="$1"
          version_was_set=1
          shift
        fi
        break
        ;;
      -*)
        printf '%s: unknown option: %s\n' "$SCRIPT_NAME" "$1" >&2
        usage_error
        ;;
      *)
        (( positional_count == 0 )) || usage_error
        (( version_was_set == 0 )) || usage_error
        version="$1"
        version_was_set=1
        positional_count=1
        shift
        ;;
    esac
  done

  (( $# == 0 )) || usage_error
  case "$action" in
    add)
      [[ -z "$profile" && -z "$version" ]] || usage_error
      (( dry_run == 0 )) || usage_error
      add_profile
      ;;
    remove)
      [[ -z "$version" ]] || usage_error
      (( dry_run == 0 )) || usage_error
      remove_profile "$profile"
      ;;
    list)
      [[ -z "$profile" && -z "$version" ]] || usage_error
      (( dry_run == 0 )) || usage_error
      load_profiles
      list_profiles
      ;;
    push)
      push_package "$profile" "$version" "$dry_run"
      ;;
  esac
}

main "$@"
