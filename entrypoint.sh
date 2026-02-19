#!/usr/bin/env bash
set -euo pipefail

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
