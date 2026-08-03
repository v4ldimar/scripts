# Shared llama.cpp path, model, and process helpers. Safe to source without performing work.

llama_init_config() {
  : "${HOME:?HOME must be set}"

  LLAMA_CPP_DIR=${LLAMA_CPP_DIR:-$HOME/llama.cpp}
  LLAMA_MODELS_DIR=${LLAMA_MODELS_DIR:-$HOME/models}
  LLAMA_CLI_BIN=${LLAMA_CLI_BIN:-$LLAMA_CPP_DIR/build/bin/llama-cli}
  LLAMA_SERVER_BIN=${LLAMA_SERVER_BIN:-$LLAMA_CPP_DIR/build/bin/llama-server}
  LLAMA_RUNTIME_DIR=${LLAMA_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/llama-tools-${UID:-user}}
  LLAMA_STATE_DIR=${LLAMA_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/llama-tools}
  LLAMA_SERVER_PID_FILE=${LLAMA_SERVER_PID_FILE:-$LLAMA_RUNTIME_DIR/server.pid}
  LLAMA_SERVER_LOG=${LLAMA_SERVER_LOG:-$LLAMA_STATE_DIR/server.log}
}

llama_die() {
  printf '%s: error: %s\n' "${0##*/}" "$*" >&2
  exit 1
}

llama_usage_error() {
  printf '%s: error: %s\n\n' "${0##*/}" "$*" >&2
  usage >&2
  exit 2
}

llama_require_executable() {
  local executable=$1
  local label=$2

  [[ -x $executable ]] || llama_die "$label is not executable: $executable"
}

llama_resolve_model() {
  local requested=$1
  local candidate=''

  if [[ $requested == */* ]]; then
    candidate=$requested
  else
    candidate=$LLAMA_MODELS_DIR/$requested
  fi

  [[ -f $candidate ]] || llama_die "model not found: $candidate"
  LLAMA_MODEL_PATH=$candidate
}

llama_list_models() {
  local model=''
  local found=0

  if [[ ! -d $LLAMA_MODELS_DIR ]]; then
    printf 'Models directory not found: %s\n' "$LLAMA_MODELS_DIR" >&2
    return 1
  fi

  while IFS= read -r -d '' model; do
    printf '%s\n' "${model##*/}"
    found=1
  done < <(find "$LLAMA_MODELS_DIR" -maxdepth 1 -type f -name '*.gguf' -print0)

  (( found == 1 )) || printf 'No .gguf models found in %s\n' "$LLAMA_MODELS_DIR" >&2
}

llama_default_threads() {
  local threads=''

  if threads=$(getconf _NPROCESSORS_ONLN 2>/dev/null) && [[ $threads =~ ^[1-9][0-9]*$ ]]; then
    printf '%s' "$threads"
  else
    printf '1'
  fi
}

llama_validate_positive_integer() {
  local value=$1
  local label=$2

  [[ $value =~ ^[1-9][0-9]*$ ]] || llama_usage_error "$label must be a positive integer"
}

llama_load_pid() {
  local pid_file=$1

  LLAMA_SERVER_PID_VALUE=''
  [[ -f $pid_file ]] || return 1
  IFS= read -r LLAMA_SERVER_PID_VALUE < "$pid_file" || return 1
  [[ $LLAMA_SERVER_PID_VALUE =~ ^[1-9][0-9]*$ ]] ||
    llama_die "invalid PID file: $pid_file"
}

llama_process_is_running() {
  local pid=$1
  kill -0 "$pid" 2>/dev/null
}

llama_pid_matches_server() {
  local pid=$1
  local command_line=''

  command_line=$(ps -p "$pid" -o args= 2>/dev/null) || return 1
  [[ $command_line == *"$LLAMA_SERVER_BIN"* ]]
}
