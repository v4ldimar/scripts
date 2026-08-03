#!/usr/bin/env bash
# Description: Start one managed llama.cpp server with configurable model, network, runtime, and model-specific options.
# Requirements: llama.cpp, coreutils, procps
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"
llama_init_config

usage() {
  cat <<EOF_USAGE
Usage: ${0##*/} [OPTIONS] MODEL [-- LLAMA_SERVER_OPTIONS...]

Options:
  --host HOST          listening host (default: $host)
  --port PORT          listening port (default: $port)
  --threads COUNT      worker threads (default: LLAMA_THREADS or detected CPUs)
  --log FILE           server log (default: $LLAMA_SERVER_LOG)
  --pid-file FILE      managed PID file (default: $LLAMA_SERVER_PID_FILE)
  --startup-wait SEC   startup check delay (default: $startup_wait)
  -h, --help           show this help

MODEL may be a filename under LLAMA_MODELS_DIR or an explicit path. Pass
model-specific llama-server arguments after --.
EOF_USAGE
}

host=${LLAMA_HOST:-0.0.0.0}
port=${LLAMA_PORT:-8080}
threads=${LLAMA_THREADS:-$(llama_default_threads)}
log_file=$LLAMA_SERVER_LOG
pid_file=$LLAMA_SERVER_PID_FILE
startup_wait=${LLAMA_STARTUP_WAIT:-2}
model=''
extra_args=()

while (($#)); do
  case $1 in
    --host|--port|--threads|--log|--pid-file|--startup-wait)
      (($# >= 2)) || llama_usage_error "missing value for $1"
      [[ -n $2 ]] || llama_usage_error "$1 requires a value"
      case $1 in
        --host) host=$2 ;;
        --port) port=$2 ;;
        --threads) threads=$2 ;;
        --log) log_file=$2 ;;
        --pid-file) pid_file=$2 ;;
        --startup-wait) startup_wait=$2 ;;
      esac
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      extra_args=("$@")
      break
      ;;
    -*) llama_usage_error "unknown option: $1" ;;
    *)
      [[ -z $model ]] || llama_usage_error "unexpected argument: $1"
      model=$1
      shift
      ;;
  esac
done

[[ -n $model ]] || llama_usage_error "MODEL is required"
[[ -n $host ]] || llama_usage_error "--host requires a value"
llama_validate_positive_integer "$port" "port"
(( port <= 65535 )) || llama_usage_error "port must be at most 65535"
llama_validate_positive_integer "$threads" "thread count"
llama_validate_positive_integer "$startup_wait" "startup wait"

command -v nohup >/dev/null 2>&1 || llama_die "nohup is not installed or not on PATH"
command -v ps >/dev/null 2>&1 || llama_die "ps is not installed or not on PATH"
llama_require_executable "$LLAMA_SERVER_BIN" "llama-server"
llama_resolve_model "$model"

if llama_load_pid "$pid_file"; then
  if llama_process_is_running "$LLAMA_SERVER_PID_VALUE"; then
    if llama_pid_matches_server "$LLAMA_SERVER_PID_VALUE"; then
      llama_die "server is already running with PID $LLAMA_SERVER_PID_VALUE"
    fi
    llama_die "PID $LLAMA_SERVER_PID_VALUE belongs to another process; remove stale file manually: $pid_file"
  fi
  rm -f -- "$pid_file" || llama_die "could not remove stale PID file: $pid_file"
fi

pid_directory=$(dirname -- "$pid_file")
log_directory=$(dirname -- "$log_file")
mkdir -p -- "$pid_directory" "$log_directory" || llama_die "could not create runtime directories"
umask 077

printf 'Starting llama-server with model %s.\n' "$LLAMA_MODEL_PATH"
nohup "$LLAMA_SERVER_BIN" \
  --model "$LLAMA_MODEL_PATH" \
  --host "$host" \
  --port "$port" \
  --threads "$threads" \
  "${extra_args[@]}" \
  >> "$log_file" 2>&1 &
server_pid=$!
printf '%s\n%s\n' "$server_pid" "$LLAMA_SERVER_BIN" > "$pid_file" || {
  if ! kill "$server_pid" 2>/dev/null; then
    printf '%s: warning: could not stop untracked server PID %s\n' "${0##*/}" "$server_pid" >&2
  fi
  llama_die "could not write PID file: $pid_file"
}

sleep "$startup_wait"
if ! llama_process_is_running "$server_pid"; then
  if wait "$server_pid"; then
    server_status=0
  else
    server_status=$?
  fi
  rm -f -- "$pid_file"
  printf '%s: server log: %s\n' "${0##*/}" "$log_file" >&2
  if ! tail -n 20 -- "$log_file" >&2; then
    printf '%s: warning: could not read server log\n' "${0##*/}" >&2
  fi
  llama_die "llama-server exited during startup with status $server_status"
fi

printf 'llama-server is running with PID %s.\n' "$server_pid"
printf 'Endpoint: http://%s:%s\n' "$host" "$port"
printf 'Log: %s\n' "$log_file"
