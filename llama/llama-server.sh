#!/bin/bash

MODELS_DIR="/home/alabot/models"

if [ -z "$1" ]; then
  echo "Usage: $0 <model-name>"
  echo "Available models:"
  ls $MODELS_DIR/*.gguf 2>/dev/null | xargs -I{} basename {}
  exit 1
fi

MODEL="$1"
MODEL_PATH="$MODELS_DIR/$MODEL"

if [ ! -f "$MODEL_PATH" ]; then
  echo "❌ Model not found: $MODEL_PATH"
  ls $MODELS_DIR/*.gguf 2>/dev/null | xargs -I{} basename {}
  exit 1
fi

echo "Killing old llama-server..."
pkill -9 -x llama-server 2>/dev/null
sleep 2 

echo "Starting: $MODEL"
nohup /home/alabot/llama.cpp/build/bin/llama-server \
  --model "$MODEL_PATH" \
  --port 8080 \
  --host 0.0.0.0 \
  --threads $(nproc) \
  --no-mmap \
  --mlock \
  --n-gpu-layers 0 \
  > llama.log 2>&1 &

LLAMA_PID=$!
sleep 8

if kill -0 $LLAMA_PID 2>/dev/null; then
  echo "✅ Running! (PID: $LLAMA_PID)"
  echo "Test: curl http://localhost:8080/v1/models"
else
  echo "❌ Crashed"
  tail -20 ~/llama.log
  free -h
fi
