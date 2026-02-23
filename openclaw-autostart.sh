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
echo "Serving onboarding instructions on port ${PORT}."

export OPENCLAW_ONBOARD_PORT="${PORT}"
export OPENCLAW_ONBOARD_COMMAND='podman compose exec openclaw onboard_script.sh && podman compose restart openclaw'

exec node -e '
const http = require("http");
const port = Number(process.env.OPENCLAW_ONBOARD_PORT || "18789");
const command = process.env.OPENCLAW_ONBOARD_COMMAND || "podman compose exec openclaw onboard_script.sh && podman compose restart openclaw";
const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>OpenClaw Setup Required</title>
  <style>
    :root { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; color-scheme: light dark; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0b1020; color: #e5e7eb; }
    main { width: min(800px, 92vw); padding: 2rem; border-radius: 14px; background: rgba(17, 24, 39, 0.92); border: 1px solid rgba(148, 163, 184, 0.25); box-shadow: 0 12px 40px rgba(2, 6, 23, 0.45); }
    h1 { margin-top: 0; font-size: 1.35rem; }
    p { line-height: 1.5; }
    code { display: block; margin-top: 0.75rem; padding: 0.85rem 1rem; border-radius: 10px; background: #020617; color: #93c5fd; overflow-x: auto; font-size: 0.95rem; }
  </style>
</head>
<body>
  <main>
    <h1>openclaw is not configured</h1>
    <p>openclaw is not configured: use this command to configure it -</p>
    <code>\`${command}\`</code>
  </main>
</body>
</html>`;

http.createServer((req, res) => {
  res.writeHead(200, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store",
  });
  res.end(html);
}).listen(port, "0.0.0.0", () => {
  console.log(`OpenClaw onboarding page listening on http://0.0.0.0:${port}`);
});
'
