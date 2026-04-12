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
sleep 5
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null

echo "Starting: $MODEL"
nohup /home/alabot/llama.cpp/build/bin/llama-server \
  --model "$MODEL_PATH" \
  --threads 4 \
  --port 8080 \
  --host 0.0.0.0 > /dev/null 2>&1 &

LLAMA_PID=$!
sleep 8

if kill -0 $LLAMA_PID 2>/dev/null; then
  echo "✅ Running! (PID: $LLAMA_PID)"
  echo "Test: curl http://localhost:8080/v1/models"
else
  echo "❌ Crashed"
  free -h
fi
