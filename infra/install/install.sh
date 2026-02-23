#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install and start local infra stack.

Usage:
  ./infra/install/install.sh [--engine docker|podman] [--no-cache] [--with-systemd-user]

Options:
  --engine            Force container engine
  --no-cache          Build images without layer cache
  --with-systemd-user Install+enable+start user systemd units instead of direct compose up

Environment:
  CONTAINER_ENGINE  Same as --engine
  OPENCLAW_IMAGE    Optional image tag used by build-images.sh and compose
EOF
  exit 1
}

ENGINE="${CONTAINER_ENGINE:-}"
NO_CACHE=0
WITH_SYSTEMD_USER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine)
      [[ $# -lt 2 ]] && usage
      ENGINE="$2"
      shift 2
      ;;
    --no-cache)
      NO_CACHE=1
      shift
      ;;
    --with-systemd-user|--systemd-user)
      WITH_SYSTEMD_USER=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "${ENGINE}" ]]; then
  if command -v podman >/dev/null 2>&1; then
    ENGINE="podman"
  elif command -v docker >/dev/null 2>&1; then
    ENGINE="docker"
  else
    echo "Error: neither podman nor docker found in PATH." >&2
    exit 1
  fi
fi

if [[ "${ENGINE}" != "podman" && "${ENGINE}" != "docker" ]]; then
  echo "Error: --engine must be either 'podman' or 'docker'." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HELPERS_DIR="${SCRIPT_DIR}/scripts"
SYSTEMD_TEMPLATE_DIR="${SCRIPT_DIR}/systemd"

if [[ ! -x "${HELPERS_DIR}/build-images.sh" ]]; then
  echo "Error: missing helper script ${HELPERS_DIR}/build-images.sh" >&2
  exit 1
fi

compose_cmd=()
if [[ "${ENGINE}" == "docker" ]]; then
  compose_cmd=("docker" "compose")
else
  if podman compose version >/dev/null 2>&1; then
    compose_cmd=("podman" "compose")
  elif command -v podman-compose >/dev/null 2>&1; then
    compose_cmd=("podman-compose")
  else
    echo "Error: podman compose plugin is unavailable (no 'podman compose' and no 'podman-compose')." >&2
    exit 1
  fi
fi

run_compose_up() {
  local stack_name="$1"
  local stack_dir="$2"
  echo "Starting stack: ${stack_name}"
  (
    cd "${stack_dir}"
    "${compose_cmd[@]}" -f ./docker-compose.yaml up -d
  )
}

create_network() {
  local network_name="$1"
  if ! "${ENGINE}" network inspect "${network_name}" >/dev/null 2>&1; then
    echo "Creating network: ${network_name}"
    "${ENGINE}" network create "${network_name}" >/dev/null
  else
    echo "Network already exists: ${network_name}"
  fi
}

OPENCLAW_ENV_FILE="${REPO_ROOT}/infra/services/ai/assistants/openclaw-local-llm/.env"
OPENCLAW_ENV_EXAMPLE="${REPO_ROOT}/infra/services/ai/assistants/openclaw-local-llm/.env.example"

if [[ ! -f "${OPENCLAW_ENV_FILE}" && -f "${OPENCLAW_ENV_EXAMPLE}" ]]; then
  echo "Creating OpenClaw .env from .env.example"
  cp "${OPENCLAW_ENV_EXAMPLE}" "${OPENCLAW_ENV_FILE}"
fi

create_network "ollama_net"

echo "Building local images..."
build_args=("all" "--repo-root" "${REPO_ROOT}" "--engine" "${ENGINE}")
if [[ "${NO_CACHE}" -eq 1 ]]; then
  build_args+=("--no-cache")
fi
"${HELPERS_DIR}/build-images.sh" "${build_args[@]}"

if [[ "${WITH_SYSTEMD_USER}" -eq 1 ]]; then
  if [[ ! -x "${HELPERS_DIR}/install-systemd-user.sh" ]]; then
    echo "Error: missing helper script ${HELPERS_DIR}/install-systemd-user.sh" >&2
    exit 1
  fi
  echo "Installing and starting user systemd units..."
  "${HELPERS_DIR}/install-systemd-user.sh" \
    --engine "${ENGINE}" \
    --repo-root "${REPO_ROOT}" \
    --template-dir "${SYSTEMD_TEMPLATE_DIR}"
else
  run_compose_up \
    "ollama" \
    "${REPO_ROOT}/infra/services/ai/ollama"

  run_compose_up \
    "openclaw-local-llm" \
    "${REPO_ROOT}/infra/services/ai/assistants/openclaw-local-llm"
fi

echo "Install finished."
