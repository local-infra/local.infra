#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "Usage: $0 <volume_name>" >&2
	exit 1
}

if [[ $# -ne 1 ]]; then
	usage
fi

if command -v docker >/dev/null 2>&1; then
	CONTAINER_TOOL=docker
elif command -v podman >/dev/null 2>&1; then
	CONTAINER_TOOL=podman
else
	echo "Error: neither docker nor podman is available in PATH." >&2
	exit 1
fi

VOLUME_NAME="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backup"
mkdir -p "${BACKUP_DIR}"

if ! "${CONTAINER_TOOL}" volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
	echo "Error: volume '${VOLUME_NAME}' does not exist." >&2
	exit 1
fi

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SAFE_VOLUME_NAME="${VOLUME_NAME//[^a-zA-Z0-9_.-]/_}"
ARCHIVE_NAME="${SAFE_VOLUME_NAME}__${TIMESTAMP}.tar"
ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"

"${CONTAINER_TOOL}" run --rm \
	-v "${VOLUME_NAME}:/from:ro" \
	-v "${BACKUP_DIR}:/backup:z" \
	debian:stable-slim \
	sh -ceu "cd /from && tar --numeric-owner -cpf /backup/${ARCHIVE_NAME} ."

echo "Backup created: ${ARCHIVE_PATH}"
