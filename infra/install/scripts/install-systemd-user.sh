#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Install user-level systemd units for AI compose stacks.

Usage:
  ./infra/install/scripts/install-systemd-user.sh [options]

Options:
  --engine docker|podman   Force engine (default: podman if available, then docker)
  --repo-root PATH         Repo root to embed into unit WorkingDirectory (required)
  --template-dir PATH      Directory with unit templates (required)
  --unit-dir PATH          Target user unit directory (default: ~/.config/systemd/user)
  --no-enable              Install units but do not enable them
  --no-start               Install units but do not start/restart them
  -h, --help               Show this help

Environment:
  CONTAINER_ENGINE         Same as --engine
EOF
	exit 1
}

ENGINE="${CONTAINER_ENGINE-}"
REPO_ROOT=""
TEMPLATE_DIR=""
UNIT_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
ENABLE_UNITS=1
START_UNITS=1

while [[ $# -gt 0 ]]; do
	case "$1" in
	--engine)
		[[ $# -lt 2 ]] && usage
		ENGINE="$2"
		shift 2
		;;
	--repo-root)
		[[ $# -lt 2 ]] && usage
		REPO_ROOT="$2"
		shift 2
		;;
	--template-dir)
		[[ $# -lt 2 ]] && usage
		TEMPLATE_DIR="$2"
		shift 2
		;;
	--unit-dir)
		[[ $# -lt 2 ]] && usage
		UNIT_DIR="$2"
		shift 2
		;;
	--no-enable)
		ENABLE_UNITS=0
		shift
		;;
	--no-start)
		START_UNITS=0
		shift
		;;
	-h | --help)
		usage
		;;
	*)
		echo "Unknown argument: $1" >&2
		usage
		;;
	esac
done

if [[ -z ${REPO_ROOT} ]]; then
	echo "Error: --repo-root is required." >&2
	usage
fi

if [[ -z ${TEMPLATE_DIR} ]]; then
	echo "Error: --template-dir is required." >&2
	usage
fi

if [[ ! -d ${REPO_ROOT} ]]; then
	echo "Error: repo root directory not found: ${REPO_ROOT}" >&2
	exit 1
fi

if [[ ! -d ${TEMPLATE_DIR} ]]; then
	echo "Error: template directory not found: ${TEMPLATE_DIR}" >&2
	exit 1
fi

REPO_ROOT="$(cd "${REPO_ROOT}" && pwd)"
TEMPLATE_DIR="$(cd "${TEMPLATE_DIR}" && pwd)"

if [[ ! -f "${REPO_ROOT}/infra/services/ai/ollama/docker-compose.yaml" ]]; then
	echo "Error: repo root seems wrong, missing ollama compose file under ${REPO_ROOT}." >&2
	exit 1
fi

if [[ ! -f "${REPO_ROOT}/infra/services/ai/assistants/openclaw-local-llm/docker-compose.yaml" ]]; then
	echo "Error: repo root seems wrong, missing openclaw compose file under ${REPO_ROOT}." >&2
	exit 1
fi

if [[ -z ${ENGINE} ]]; then
	if command -v podman >/dev/null 2>&1; then
		ENGINE="podman"
	elif command -v docker >/dev/null 2>&1; then
		ENGINE="docker"
	else
		echo "Error: neither podman nor docker found in PATH." >&2
		exit 1
	fi
fi

if [[ ${ENGINE} != "podman" && ${ENGINE} != "docker" ]]; then
	echo "Error: --engine must be either 'podman' or 'docker'." >&2
	exit 1
fi

ENGINE_BIN=""
COMPOSE_CMD=""

if [[ ${ENGINE} == "docker" ]]; then
	ENGINE_BIN="$(command -v docker || true)"
	if [[ -z ${ENGINE_BIN} ]]; then
		echo "Error: docker binary not found in PATH." >&2
		exit 1
	fi
	if ! docker compose version >/dev/null 2>&1; then
		echo "Error: docker compose plugin is unavailable." >&2
		exit 1
	fi
	COMPOSE_CMD="${ENGINE_BIN} compose"
else
	ENGINE_BIN="$(command -v podman || true)"
	if [[ -z ${ENGINE_BIN} ]]; then
		echo "Error: podman binary not found in PATH." >&2
		exit 1
	fi

	if podman compose version >/dev/null 2>&1; then
		COMPOSE_CMD="${ENGINE_BIN} compose"
	elif command -v podman-compose >/dev/null 2>&1; then
		COMPOSE_CMD="$(command -v podman-compose)"
	else
		echo "Error: podman compose is unavailable (no 'podman compose' and no 'podman-compose')." >&2
		exit 1
	fi
fi

escape_sed_replacement() {
	printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

CURRENT_USER="$(id -un)"
CURRENT_UID="$(id -u)"
SYSTEMCTL_USER_PREFIX=()

ensure_user_bus_env() {
	if [[ -z "${XDG_RUNTIME_DIR-}" ]]; then
		export XDG_RUNTIME_DIR="/run/user/${CURRENT_UID}"
	fi

	if [[ -z "${DBUS_SESSION_BUS_ADDRESS-}" ]]; then
		export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
	fi
}

maybe_start_user_manager() {
	if [[ ${EUID} -eq 0 ]]; then
		systemctl start "user@${CURRENT_UID}.service" >/dev/null 2>&1 || true
	fi
}

resolve_systemctl_user_prefix() {
	if systemctl --user show-environment >/dev/null 2>&1; then
		SYSTEMCTL_USER_PREFIX=("systemctl" "--user")
		return 0
	fi

	ensure_user_bus_env
	maybe_start_user_manager
	if systemctl --user show-environment >/dev/null 2>&1; then
		SYSTEMCTL_USER_PREFIX=("systemctl" "--user")
		return 0
	fi

	if systemctl --machine="${CURRENT_USER}@.host" --user show-environment >/dev/null 2>&1; then
		SYSTEMCTL_USER_PREFIX=("systemctl" "--machine=${CURRENT_USER}@.host" "--user")
		return 0
	fi

	return 1
}

run_systemctl_user() {
	"${SYSTEMCTL_USER_PREFIX[@]}" "$@"
}

render_unit() {
	local template_file="$1"
	local output_file="$2"
	local escaped_repo_root=""
	local escaped_engine_bin=""
	local escaped_compose_cmd=""

	escaped_repo_root="$(escape_sed_replacement "${REPO_ROOT}")"
	escaped_engine_bin="$(escape_sed_replacement "${ENGINE_BIN}")"
	escaped_compose_cmd="$(escape_sed_replacement "${COMPOSE_CMD}")"

	sed \
		-e "s/__REPO_ROOT__/${escaped_repo_root}/g" \
		-e "s/__ENGINE_BIN__/${escaped_engine_bin}/g" \
		-e "s/__COMPOSE_CMD__/${escaped_compose_cmd}/g" \
		"${template_file}" >"${output_file}"
}

mkdir -p "${UNIT_DIR}"

render_unit \
	"${TEMPLATE_DIR}/ai-ollama.service" \
	"${UNIT_DIR}/ai-ollama.service"

render_unit \
	"${TEMPLATE_DIR}/ai-openclaw.service" \
	"${UNIT_DIR}/ai-openclaw.service"

echo "Installed units into ${UNIT_DIR}:"
echo "  ai-ollama.service"
echo "  ai-openclaw.service"

if ! resolve_systemctl_user_prefix; then
	echo "Error: unable to connect to user systemd manager for ${CURRENT_USER}." >&2
	echo "Try initializing the user manager and exporting runtime bus variables, then rerun:" >&2
	echo "  sudo loginctl enable-linger ${CURRENT_USER}" >&2
	echo "  sudo systemctl start user@${CURRENT_UID}.service" >&2
	echo "  export XDG_RUNTIME_DIR=/run/user/${CURRENT_UID}" >&2
	echo "  export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${CURRENT_UID}/bus" >&2
	exit 1
fi

if [[ "${SYSTEMCTL_USER_PREFIX[*]}" == *"--machine="* ]]; then
	echo "No active user session bus detected; using ${SYSTEMCTL_USER_PREFIX[*]}."
fi

if [[ ${ENGINE} == "podman" ]]; then
	if run_systemctl_user list-unit-files podman.socket >/dev/null 2>&1; then
		run_systemctl_user enable --now podman.socket
	else
		echo "Warning: podman.socket unit not found; compose provider may require manual Podman API setup." >&2
	fi
fi

run_systemctl_user daemon-reload

if [[ ${ENABLE_UNITS} -eq 1 ]]; then
	run_systemctl_user enable ai-ollama.service ai-openclaw.service
fi

if [[ ${START_UNITS} -eq 1 ]]; then
	run_systemctl_user restart ai-ollama.service
	run_systemctl_user restart ai-openclaw.service
fi

echo
echo "Control commands:"
echo "  systemctl --user status ai-ollama.service ai-openclaw.service"
echo "  systemctl --user restart ai-ollama.service"
echo "  systemctl --user restart ai-openclaw.service"
echo "  systemctl --user stop ai-openclaw.service"
echo "  systemctl --user disable --now ai-openclaw.service"

if command -v loginctl >/dev/null 2>&1; then
	LINGER_STATE="$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)"
	if [[ ${LINGER_STATE} != "yes" ]]; then
		echo
		echo "Boot autostart requires linger for this user:"
		echo "  sudo loginctl enable-linger $(id -un)"
	fi
fi
