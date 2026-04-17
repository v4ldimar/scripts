#!/bin/bash

echo "Stopping llama-server..."

# Try graceful shutdown first

pkill -x llama-server 2>/dev/null

sleep 2

# Check if it's still running

if pgrep -x llama-server > /dev/null; then
echo "⚠️ Still running, forcing kill..."
pkill -9 -x llama-server 2>/dev/null
sleep 1
fi

# Final check

if pgrep -x llama-server > /dev/null; then
echo "❌ Failed to stop llama-server"
exit 1
else
echo "✅ llama-server stopped"
fi

