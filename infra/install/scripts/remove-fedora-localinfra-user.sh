#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Remove a Fedora local service user and related helper artifacts.

Usage:
  sudo ./infra/install/scripts/remove-fedora-localinfra-user.sh --username NAME [--delete-home]

Required options:
  --username NAME   Linux account name to remove

Optional:
  --delete-home     Remove the user's home directory (default: preserve home)
EOF
  exit 1
}

USERNAME=""
DELETE_HOME=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --username)
      [[ $# -lt 2 ]] && usage
      USERNAME="$2"
      shift 2
      ;;
    --delete-home)
      DELETE_HOME=1
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

if [[ -z "${USERNAME}" ]]; then
  echo "Error: --username is required." >&2
  usage
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Error: run as root (for example: sudo ...)." >&2
  exit 1
fi

if ! [[ "${USERNAME}" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
  echo "Error: invalid username '${USERNAME}'." >&2
  exit 1
fi

HOME_DIR="/home/${USERNAME}"
if id "${USERNAME}" >/dev/null 2>&1; then
  HOME_DIR="$(getent passwd "${USERNAME}" | cut -d: -f6)"
fi

if command -v loginctl >/dev/null 2>&1; then
  loginctl terminate-user "${USERNAME}" 2>/dev/null || true
  loginctl disable-linger "${USERNAME}" 2>/dev/null || true
fi

pkill -u "${USERNAME}" 2>/dev/null || true

if id "${USERNAME}" >/dev/null 2>&1; then
  if ! userdel "${USERNAME}"; then
    echo "Error: failed to remove user '${USERNAME}'." >&2
    exit 1
  fi
  groupdel "${USERNAME}" 2>/dev/null || true
fi

if [[ "${DELETE_HOME}" -eq 1 ]]; then
  if [[ -n "${HOME_DIR}" && "${HOME_DIR}" != "/" && "${HOME_DIR}" != "/home" && -d "${HOME_DIR}" ]]; then
    rm -rf --one-file-system "${HOME_DIR}"
  fi
fi

if [[ -f /etc/subuid ]]; then
  SUBUID_TMP="$(mktemp /etc/subuid.XXXXXX)"
  awk -F: -v user_name="${USERNAME}" '$1 != user_name { print }' /etc/subuid >"${SUBUID_TMP}"
  mv "${SUBUID_TMP}" /etc/subuid
  chmod 644 /etc/subuid
fi

if [[ -f /etc/subgid ]]; then
  SUBGID_TMP="$(mktemp /etc/subgid.XXXXXX)"
  awk -F: -v user_name="${USERNAME}" '$1 != user_name { print }' /etc/subgid >"${SUBGID_TMP}"
  mv "${SUBGID_TMP}" /etc/subgid
  chmod 644 /etc/subgid
fi

rm -f "/var/lib/AccountsService/users/${USERNAME}"

SSH_DENY_FILE="/etc/ssh/sshd_config.d/90-deny-${USERNAME}.conf"
rm -f "${SSH_DENY_FILE}"

if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet sshd; then
    systemctl reload sshd || true
  elif systemctl is-active --quiet ssh; then
    systemctl reload ssh || true
  fi

  if systemctl list-unit-files accounts-daemon.service >/dev/null 2>&1; then
    systemctl restart accounts-daemon >/dev/null 2>&1 || true
  fi
fi

echo "Done."
echo "Removed user: ${USERNAME}"
echo "Removed SSH deny file: ${SSH_DENY_FILE}"
if [[ "${DELETE_HOME}" -eq 1 ]]; then
  echo "Home directory removed: ${HOME_DIR}"
else
  echo "Home directory preserved: ${HOME_DIR}"
fi
