#!/usr/bin/env bash
set -euo pipefail

# Work around onboarding bind issues by enforcing a final gateway.bind value.
FORCE_BIND="${OPENCLAW_ONBOARD_FORCE_BIND:-lan}"

if [[ $# -eq 0 ]]; then
	echo "Running: openclaw onboard --install-daemon"
	openclaw onboard --install-daemon
else
	echo "Running: openclaw onboard $*"
	openclaw onboard "$@"
fi

echo "Setting gateway.bind=${FORCE_BIND} in openclaw.json"
openclaw config set gateway.bind "${FORCE_BIND}"

echo "Done. Current gateway.bind:"
openclaw config get gateway.bind
