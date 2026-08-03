#!/usr/bin/env bash
# Description: Run llama.cpp's CLI with a model selected by filename or path.
# Requirements: llama.cpp
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
# shellcheck source=lib/runtime.sh
source "$SCRIPT_DIR/lib/runtime.sh"
llama_init_config

usage() {
  cat <<EOF_USAGE
Usage: ${0##*/} MODEL [LLAMA_CLI_OPTIONS...]
       ${0##*/} --list-models

MODEL may be a filename under LLAMA_MODELS_DIR or an explicit path.

Environment:
  LLAMA_CPP_DIR     llama.cpp checkout (default: ~/llama.cpp)
  LLAMA_CLI_BIN     llama-cli executable
  LLAMA_MODELS_DIR  model directory (default: ~/models)
EOF_USAGE
}

case ${1-} in
  -h|--help)
    usage
    exit 0
    ;;
  --list-models)
    (($# == 1)) || llama_usage_error "--list-models does not accept arguments"
    llama_list_models
    exit 0
    ;;
  '') llama_usage_error "MODEL is required" ;;
esac

model=$1
shift

llama_require_executable "$LLAMA_CLI_BIN" "llama-cli"
llama_resolve_model "$model"

exec "$LLAMA_CLI_BIN" --model "$LLAMA_MODEL_PATH" "$@"
