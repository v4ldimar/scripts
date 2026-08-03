#!/usr/bin/env bash
# Description: Restore the Windows time zone saved by set-norway.sh, or set an explicitly supplied local time zone.
set -euo pipefail

PROGRAM=${0##*/}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly PROGRAM SCRIPT_DIR
# shellcheck source=lib/windows-timezone.sh
source "$SCRIPT_DIR/lib/windows-timezone.sh"
readonly STATE_FILE="${WINDOWS_TIMEZONE_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/scripts/windows-timezone/previous-timezone}"

usage() {
  cat <<EOF_USAGE
Usage: $PROGRAM [--timezone WINDOWS_TIMEZONE_ID]

Options:
  -t, --timezone ID  Restore to ID instead of the saved time zone
  -h, --help         Show this help

WINDOWS_LOCAL_TIMEZONE_ID is used when no saved state or --timezone value exists.
EOF_USAGE
}

die() {
  printf '%s: error: %s\n' "$PROGRAM" "$*" >&2
  exit 1
}

usage_error() {
  printf '%s: error: %s\n\n' "$PROGRAM" "$*" >&2
  usage >&2
  exit 2
}

timezone_id=''
remove_state=0

while (($#)); do
  case $1 in
    -t|--timezone)
      (($# >= 2)) || usage_error "missing value for $1"
      timezone_id=$2
      [[ -n $timezone_id ]] || usage_error "$1 requires a value"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) usage_error "unexpected argument: $1" ;;
  esac
done

windows_timezone_require_tzutil ||
  die "tzutil.exe is unavailable; run this script from Git Bash or WSL on Windows"

if [[ -z $timezone_id && -f $STATE_FILE ]]; then
  IFS= read -r timezone_id < "$STATE_FILE" ||
    die "could not read saved time zone from $STATE_FILE"
  timezone_id=${timezone_id//$'\r'/}
  remove_state=1
fi

timezone_id=${timezone_id:-${WINDOWS_LOCAL_TIMEZONE_ID:-}}
[[ -n $timezone_id ]] ||
  die "no saved time zone; pass --timezone ID or set WINDOWS_LOCAL_TIMEZONE_ID"
[[ $timezone_id != *$'\n'* && $timezone_id != *$'\r'* ]] ||
  die "time-zone identifier must be a single line"

if ! windows_timezone_set "$timezone_id"; then
  die "could not set Windows time zone to $timezone_id"
fi

active_timezone=$(windows_timezone_get) || die "time zone changed, but verification failed"
[[ $active_timezone == "$timezone_id" ]] ||
  die "expected $timezone_id after update, got $active_timezone"

if (( remove_state )); then
  rm -f -- "$STATE_FILE" || die "time zone restored, but saved state could not be removed"
fi

printf 'Windows time zone is now %s.\n' "$active_timezone"
