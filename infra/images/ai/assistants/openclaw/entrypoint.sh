#!/usr/bin/env bash
set -euo pipefail

# Start local proxy so anything in this container can reach Ollama at 127.0.0.1:11434.
# OpenClaw auto-discovery expects http://127.0.0.1:11434
# We proxy that to the compose service "ollama:11434"
if ! ss -lnt 2>/dev/null | grep -q ':11434'; then
  echo "Starting socat proxy: 127.0.0.1:11434 -> ollama:11434"
  socat TCP-LISTEN:11434,bind=127.0.0.1,fork,reuseaddr TCP:ollama:11434 &
fi

exec "$@"
