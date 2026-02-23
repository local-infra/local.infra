#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build local infra images.

Usage:
  ./infra/install/scripts/build-images.sh [target] --repo-root PATH [--engine docker|podman] [--no-cache]

Targets:
  openclaw   Build OpenClaw image
  all        Build all images (currently same as openclaw)

Environment:
  OPENCLAW_IMAGE      Tag for OpenClaw image (default: localhost/openclaw:fedora43)
  CONTAINER_ENGINE    Force container engine (docker or podman)
EOF
  exit 1
}

TARGET="all"
ENGINE="${CONTAINER_ENGINE:-}"
NO_CACHE=0
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    openclaw|all)
      TARGET="$1"
      shift
      ;;
    --repo-root)
      [[ $# -lt 2 ]] && usage
      REPO_ROOT="$2"
      shift 2
      ;;
    --engine)
      [[ $# -lt 2 ]] && usage
      ENGINE="$2"
      shift 2
      ;;
    --no-cache)
      NO_CACHE=1
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

if [[ -z "${REPO_ROOT}" ]]; then
  echo "Error: --repo-root is required." >&2
  usage
fi

REPO_ROOT="$(cd "${REPO_ROOT}" && pwd)"

OPENCLAW_CONTEXT="${REPO_ROOT}/infra/images/ai/assistants/openclaw"
OPENCLAW_DOCKERFILE="${OPENCLAW_CONTEXT}/Dockerfile.openclaw"
OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-localhost/openclaw:fedora43}"

if [[ ! -d "${OPENCLAW_CONTEXT}" ]]; then
  echo "Error: OpenClaw build context not found: ${OPENCLAW_CONTEXT}" >&2
  exit 1
fi

if [[ ! -f "${OPENCLAW_DOCKERFILE}" ]]; then
  echo "Error: OpenClaw Dockerfile not found: ${OPENCLAW_DOCKERFILE}" >&2
  exit 1
fi

build_openclaw() {
  local args=()
  if [[ "${NO_CACHE}" -eq 1 ]]; then
    args+=(--no-cache)
  fi

  echo "Building ${OPENCLAW_IMAGE} with ${ENGINE}..."
  "${ENGINE}" build \
    "${args[@]}" \
    -t "${OPENCLAW_IMAGE}" \
    -f "${OPENCLAW_DOCKERFILE}" \
    "${OPENCLAW_CONTEXT}"
}

case "${TARGET}" in
  openclaw|all)
    build_openclaw
    ;;
  *)
    usage
    ;;
esac

echo "Build finished."
