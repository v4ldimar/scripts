#!/usr/bin/env bash
# Description: Save the current Windows time zone and switch to the Norway time zone.
set -euo pipefail

PROGRAM=${0##*/}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly PROGRAM SCRIPT_DIR
# shellcheck source=lib/windows-timezone.sh
source "$SCRIPT_DIR/lib/windows-timezone.sh"
readonly NORWAY_TIMEZONE_ID="${WINDOWS_NORWAY_TIMEZONE_ID:-W. Europe Standard Time}"
readonly STATE_FILE="${WINDOWS_TIMEZONE_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/scripts/windows-timezone/previous-timezone}"

usage() {
  printf 'Usage: %s\n' "$PROGRAM"
}

die() {
  printf '%s: error: %s\n' "$PROGRAM" "$*" >&2
  exit 1
}

case ${1-} in
  -h|--help)
    usage
    exit 0
    ;;
  '') ;;
  *)
    printf '%s: error: unexpected argument: %s\n\n' "$PROGRAM" "$1" >&2
    usage >&2
    exit 2
    ;;
esac

windows_timezone_require_tzutil ||
  die "tzutil.exe is unavailable; run this script from Git Bash or WSL on Windows"

current_timezone=$(windows_timezone_get) || die "could not read the current Windows time zone"

if [[ $current_timezone == "$NORWAY_TIMEZONE_ID" ]]; then
  printf 'Windows time zone is already %s.\n' "$NORWAY_TIMEZONE_ID"
  exit 0
fi

state_directory=$(dirname -- "$STATE_FILE")
mkdir -p -- "$state_directory" || die "could not create state directory: $state_directory"

created_state=0
if [[ -e $STATE_FILE ]]; then
  printf '%s: preserving existing restore state: %s\n' "$PROGRAM" "$STATE_FILE" >&2
else
  umask 077
  printf '%s\n' "$current_timezone" > "$STATE_FILE" ||
    die "could not save the current time zone to $STATE_FILE"
  created_state=1
fi

if ! windows_timezone_set "$NORWAY_TIMEZONE_ID"; then
  (( created_state == 0 )) || rm -f -- "$STATE_FILE"
  die "could not set Windows time zone to $NORWAY_TIMEZONE_ID"
fi

active_timezone=$(windows_timezone_get) || die "time zone changed, but verification failed"
[[ $active_timezone == "$NORWAY_TIMEZONE_ID" ]] ||
  die "expected $NORWAY_TIMEZONE_ID after update, got $active_timezone"

printf 'Windows time zone changed from %s to %s.\n' "$current_timezone" "$active_timezone"
printf 'Restore it with restore-local.sh.\n'
