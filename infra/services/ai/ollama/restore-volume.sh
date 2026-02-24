#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <volume_name>" >&2
  exit 1
}

if [[ "$#" -ne 1 ]]; then
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

if [[ ! -d "${BACKUP_DIR}" ]]; then
  echo "Error: backup directory not found: ${BACKUP_DIR}" >&2
  exit 1
fi

SAFE_VOLUME_NAME="${VOLUME_NAME//[^a-zA-Z0-9_.-]/_}"

latest_archive_from_globs() {
  local latest=""
  local f=""

  for f in "$@"; do
    if [[ ! -e "${f}" ]]; then
      continue
    fi

    if [[ -z "${latest}" ]] || [[ "${f}" -nt "${latest}" ]]; then
      latest="${f}"
    fi
  done

  printf '%s' "${latest}"
}

LATEST_ARCHIVE_MATCHING="$(
  latest_archive_from_globs \
    "${BACKUP_DIR}/${SAFE_VOLUME_NAME}__"*.tar \
    "${BACKUP_DIR}/${SAFE_VOLUME_NAME}__"*.tar.gz
)"
LATEST_ARCHIVE_ANY="$(
  latest_archive_from_globs \
    "${BACKUP_DIR}/"*.tar \
    "${BACKUP_DIR}/"*.tar.gz
)"

if [[ -n "${LATEST_ARCHIVE_MATCHING}" ]]; then
  LATEST_ARCHIVE="${LATEST_ARCHIVE_MATCHING}"
else
  LATEST_ARCHIVE="${LATEST_ARCHIVE_ANY}"
fi

if [[ -z "${LATEST_ARCHIVE}" ]]; then
  echo "Error: no backup archive found in ${BACKUP_DIR}" >&2
  exit 1
fi

if ! "${CONTAINER_TOOL}" volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
  "${CONTAINER_TOOL}" volume create "${VOLUME_NAME}" >/dev/null
fi

ARCHIVE_BASENAME="$(basename "${LATEST_ARCHIVE}")"

if [[ "${ARCHIVE_BASENAME}" == *.tar.gz ]]; then
  TAR_EXTRACT_FLAGS="-xzpf"
else
  TAR_EXTRACT_FLAGS="-xpf"
fi

"${CONTAINER_TOOL}" run --rm \
  -v "${VOLUME_NAME}:/to:z" \
  -v "${BACKUP_DIR}:/backup:ro,z" \
  debian:stable-slim \
  sh -ceu "cd /to && tar --numeric-owner ${TAR_EXTRACT_FLAGS} /backup/${ARCHIVE_BASENAME}"

echo "Restore completed from: ${LATEST_ARCHIVE}"
echo "Target volume: ${VOLUME_NAME}"
