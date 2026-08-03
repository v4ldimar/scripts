#!/usr/bin/env bash
# Description: Stop the llama.cpp server recorded in the managed PID file, escalating to SIGKILL only after a timeout.
# Requirements: procps
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"
llama_init_config

usage() {
  cat <<EOF_USAGE
Usage: ${0##*/} [OPTIONS]

Options:
  --pid-file FILE  managed PID file (default: $LLAMA_SERVER_PID_FILE)
  --timeout SEC    seconds to wait before SIGKILL (default: $timeout)
  -h, --help       show this help
EOF_USAGE
}

pid_file=$LLAMA_SERVER_PID_FILE
timeout=${LLAMA_STOP_TIMEOUT:-10}

while (($#)); do
  case $1 in
    --pid-file|--timeout)
      (($# >= 2)) || llama_usage_error "missing value for $1"
      [[ -n $2 ]] || llama_usage_error "$1 requires a value"
      case $1 in
        --pid-file) pid_file=$2 ;;
        --timeout) timeout=$2 ;;
      esac
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) llama_usage_error "unexpected argument: $1" ;;
  esac
done

llama_validate_positive_integer "$timeout" "timeout"
command -v ps >/dev/null 2>&1 || llama_die "ps is not installed or not on PATH"

if ! llama_load_pid "$pid_file"; then
  printf 'No managed llama-server PID file found at %s.\n' "$pid_file"
  exit 0
fi

pid=$LLAMA_SERVER_PID_VALUE
if ! llama_process_is_running "$pid"; then
  rm -f -- "$pid_file" || llama_die "could not remove stale PID file: $pid_file"
  printf 'Removed stale PID file; llama-server was not running.\n'
  exit 0
fi

llama_pid_matches_server "$pid" ||
  llama_die "refusing to signal PID $pid because it does not match $LLAMA_SERVER_BIN"

printf 'Stopping llama-server with PID %s.\n' "$pid"
kill -TERM "$pid" || llama_die "could not send SIGTERM to PID $pid"

deadline=$((SECONDS + timeout))
while llama_process_is_running "$pid" && (( SECONDS < deadline )); do
  sleep 0.2
done

if llama_process_is_running "$pid"; then
  printf '%s: server did not stop within %s seconds; sending SIGKILL\n' "${0##*/}" "$timeout" >&2
  kill -KILL "$pid" || llama_die "could not send SIGKILL to PID $pid"
  for (( attempt=0; attempt<25; attempt++ )); do
    llama_process_is_running "$pid" || break
    sleep 0.2
  done
fi

llama_process_is_running "$pid" && llama_die "llama-server process $pid is still running"
rm -f -- "$pid_file" || llama_die "server stopped, but PID file could not be removed"
printf 'llama-server stopped.\n'
