#!/usr/bin/env bash
set -euo pipefail

# --- 0) Ensure Ollama key for implicit discovery (any value works) ---
export OLLAMA_API_KEY="${OLLAMA_API_KEY:-ollama-local}"

# --- 1) Start local proxy so OpenClaw can reach Ollama at 127.0.0.1:11434 ---
# OpenClaw auto-discovery expects http://127.0.0.1:11434
# We proxy that to the compose service "ollama:11434"
if ! ss -lnt 2>/dev/null | grep -q ':11434'; then
  echo "Starting socat proxy: 127.0.0.1:11434 -> ollama:11434"
  socat TCP-LISTEN:11434,bind=127.0.0.1,fork,reuseaddr TCP:ollama:11434 &
fi

CFG_DIR="${HOME}/.openclaw"
CFG_FILE="${CFG_DIR}/openclaw.json"

mkdir -p "${CFG_DIR}"

if [[ ! -f "${CFG_FILE}" ]]; then
  TOKEN="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
  )"

  cat > "${CFG_FILE}" <<JSON
{
  "gateway": {
    "mode": "local",
    "auth": {
      "token": "${TOKEN}"
    }
  }
}
JSON

  chmod 700 "${CFG_DIR}"
  chmod 600 "${CFG_FILE}"

  echo "Generated ${CFG_FILE}"
  echo "Gateway token: ${TOKEN}"
fi

exec "$@"
