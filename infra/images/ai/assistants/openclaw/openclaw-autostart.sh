#!/usr/bin/env bash
set -euo pipefail

PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
STATE_DIR="${OPENCLAW_STATE_DIR:-${HOME}/.openclaw}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${STATE_DIR}/openclaw.json}"

if [[ -f ${CONFIG_PATH} ]]; then
	echo "OpenClaw config found at ${CONFIG_PATH}. Starting gateway on port ${PORT}."
	openclaw config get gateway.auth.token
	exec openclaw gateway --port "${PORT}" --verbose
fi

echo "OpenClaw is not configured yet (${CONFIG_PATH} not found)."
echo "Starting browser onboarding terminal on port ${PORT}."

if command -v ttyd >/dev/null 2>&1; then
	WEBTTY_AUTH="${OPENCLAW_WEBTTY_AUTH:-}"
	WEBTTY_INIT_CMD="${OPENCLAW_WEBTTY_INIT_CMD:-onboard_script.sh}"
	TTYD_WRITABLE_FLAG=""

	if ttyd --help 2>&1 | grep -q -- "--writable"; then
		TTYD_WRITABLE_FLAG="--writable"
	elif ttyd --help 2>&1 | grep -q -- "-W"; then
		TTYD_WRITABLE_FLAG="-W"
	fi

	if [[ -n "${TTYD_WRITABLE_FLAG}" ]]; then
		echo "ttyd writable mode enabled (${TTYD_WRITABLE_FLAG})."
	else
		echo "WARNING: ttyd writable flag not found; keyboard input may be limited."
	fi

	while [[ ! -f ${CONFIG_PATH} ]]; do
		echo "Waiting for onboarding via browser terminal at http://0.0.0.0:${PORT}"
		echo "Web terminal command: ${WEBTTY_INIT_CMD}"

		set +e
		TTYD_ARGS=(-i 0.0.0.0 -p "${PORT}")
		if [[ -n "${TTYD_WRITABLE_FLAG}" ]]; then
			TTYD_ARGS+=("${TTYD_WRITABLE_FLAG}")
		fi
		if [[ -n "${WEBTTY_AUTH}" ]]; then
			echo "Web terminal auth is enabled."
			TTYD_ARGS+=(-c "${WEBTTY_AUTH}")
			ttyd "${TTYD_ARGS[@]}" bash -lc "${WEBTTY_INIT_CMD}"
		else
			ttyd "${TTYD_ARGS[@]}" bash -lc "${WEBTTY_INIT_CMD}"
		fi
		TTYD_RC=$?
		set -e

		if [[ -f ${CONFIG_PATH} ]]; then
			break
		fi

		echo "Onboarding did not produce ${CONFIG_PATH} (ttyd exited ${TTYD_RC}). Restarting terminal in 2s."
		sleep 2
	done

	echo "OpenClaw config found at ${CONFIG_PATH}. Starting gateway on port ${PORT}."
	openclaw config get gateway.auth.token || true
	exec openclaw gateway --port "${PORT}" --verbose
fi

echo "WARNING: ttyd not found. Falling back to static onboarding instructions."
export OPENCLAW_ONBOARD_PORT="${PORT}"
export OPENCLAW_ONBOARD_COMMAND='podman compose exec openclaw onboard_script.sh && podman compose restart openclaw'

exec node -e '
const http = require("http");
const port = Number(process.env.OPENCLAW_ONBOARD_PORT || "18789");
const command = process.env.OPENCLAW_ONBOARD_COMMAND || "podman compose exec openclaw onboard_script.sh && podman compose restart openclaw";
const html = `<!doctype html>
<html lang="en">
<head><meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" /><title>OpenClaw Setup Required</title></head>
<body style="font-family: sans-serif; margin: 2rem;">
  <h1>openclaw is not configured</h1>
  <p>Run onboarding from host:</p>
  <pre style="padding: 1rem; background: #f4f4f5; border-radius: 8px;">${command}</pre>
</body>
</html>`;
http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
  res.end(html);
}).listen(port, "0.0.0.0", () => {
  console.log(`OpenClaw onboarding page listening on http://0.0.0.0:${port}`);
});
'
