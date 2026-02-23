#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Create a Fedora local service user that is hidden in GDM, denied in SSH, linger-enabled,
and ready for rootless Podman (subuid/subgid mappings).

Usage:
  sudo ./infra/install/scripts/create-fedora-localinfra-user.sh --username NAME --homedir PATH

Required options:
  --username NAME   Linux account name to create/configure
  --homedir PATH    Absolute path for the user's home directory

Optional:
  --shell PATH      Login shell for local su/sudo sessions (default: /bin/bash)
  -h, --help        Show this help
EOF
  exit 1
}

USERNAME=""
HOME_DIR=""
SHELL_PATH="/bin/bash"
SUBID_BLOCK_SIZE=65536

while [[ $# -gt 0 ]]; do
  case "$1" in
    --username)
      [[ $# -lt 2 ]] && usage
      USERNAME="$2"
      shift 2
      ;;
    --homedir)
      [[ $# -lt 2 ]] && usage
      HOME_DIR="$2"
      shift 2
      ;;
    --shell)
      [[ $# -lt 2 ]] && usage
      SHELL_PATH="$2"
      shift 2
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

if [[ -z "${USERNAME}" || -z "${HOME_DIR}" ]]; then
  echo "Error: --username and --homedir are required." >&2
  usage
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Error: run as root (for example: sudo ...)." >&2
  exit 1
fi

if [[ "${HOME_DIR}" != /* ]]; then
  echo "Error: --homedir must be an absolute path." >&2
  exit 1
fi

if ! [[ "${USERNAME}" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
  echo "Error: invalid username '${USERNAME}'." >&2
  exit 1
fi

if [[ ! -x "${SHELL_PATH}" ]]; then
  echo "Error: shell path does not exist or is not executable: ${SHELL_PATH}" >&2
  exit 1
fi

ensure_subid_file() {
  local file_path="$1"
  if [[ ! -e "${file_path}" ]]; then
    install -m 644 -o root -g root /dev/null "${file_path}"
  fi
}

next_subid_start() {
  local file_path="$1"
  local min_start=100000

  awk -F: -v min_start="${min_start}" '
    $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {
      end = $2 + $3 - 1
      if (end > max_end) {
        max_end = end
      }
    }
    END {
      if (max_end < min_start) {
        print min_start
      } else {
        print max_end + 1
      }
    }
  ' "${file_path}"
}

has_subid_mapping() {
  local file_path="$1"
  awk -F: -v user_name="${USERNAME}" '
    $1 == user_name && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "${file_path}"
}

ensure_subid_mapping() {
  local file_path="$1"
  local kind="$2" # "uid" or "gid"
  local start_id=""
  local end_id=""
  local usermod_arg=""

  if has_subid_mapping "${file_path}"; then
    return
  fi

  start_id="$(next_subid_start "${file_path}")"
  end_id=$((start_id + SUBID_BLOCK_SIZE - 1))

  if [[ "${kind}" == "uid" ]]; then
    usermod_arg="--add-subuids"
  else
    usermod_arg="--add-subgids"
  fi

  if usermod "${usermod_arg}" "${start_id}-${end_id}" "${USERNAME}" >/dev/null 2>&1; then
    return
  fi

  echo "${USERNAME}:${start_id}:${SUBID_BLOCK_SIZE}" >>"${file_path}"
}

if id "${USERNAME}" >/dev/null 2>&1; then
  CURRENT_HOME="$(getent passwd "${USERNAME}" | cut -d: -f6)"
  if [[ "${CURRENT_HOME}" != "${HOME_DIR}" ]]; then
    echo "Error: user '${USERNAME}' already exists with home '${CURRENT_HOME}', requested '${HOME_DIR}'." >&2
    exit 1
  fi
  echo "User already exists: ${USERNAME}"
else
  useradd \
    --system \
    --create-home \
    --home-dir "${HOME_DIR}" \
    --shell "${SHELL_PATH}" \
    --user-group \
    "${USERNAME}"
  echo "Created user: ${USERNAME}"
fi

PRIMARY_GROUP="$(id -gn "${USERNAME}")"
install -d -m 700 -o "${USERNAME}" -g "${PRIMARY_GROUP}" "${HOME_DIR}"

ensure_subid_file "/etc/subuid"
ensure_subid_file "/etc/subgid"
ensure_subid_mapping "/etc/subuid" "uid"
ensure_subid_mapping "/etc/subgid" "gid"

# Disable password-based login (still usable via root/sudo su).
passwd -l "${USERNAME}" >/dev/null

install -d -m 755 /var/lib/AccountsService/users
cat >"/var/lib/AccountsService/users/${USERNAME}" <<EOF
[User]
SystemAccount=true
Hidden=true
EOF
chown root:root "/var/lib/AccountsService/users/${USERNAME}"
chmod 600 "/var/lib/AccountsService/users/${USERNAME}"

if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files accounts-daemon.service >/dev/null 2>&1; then
    systemctl restart accounts-daemon >/dev/null 2>&1 || true
  fi
fi

if command -v loginctl >/dev/null 2>&1; then
  if ! loginctl enable-linger "${USERNAME}"; then
    echo "Error: failed to enable linger for ${USERNAME}." >&2
    exit 1
  fi
else
  echo "Warning: loginctl not found; linger was not enabled." >&2
fi

install -d -m 755 /etc/ssh/sshd_config.d
SSH_DENY_FILE="/etc/ssh/sshd_config.d/90-deny-${USERNAME}.conf"
cat >"${SSH_DENY_FILE}" <<EOF
DenyUsers ${USERNAME}
EOF
chown root:root "${SSH_DENY_FILE}"
chmod 600 "${SSH_DENY_FILE}"

SSH_SERVICE=""
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet sshd; then
    SSH_SERVICE="sshd"
  elif systemctl is-active --quiet ssh; then
    SSH_SERVICE="ssh"
  fi
fi

if command -v sshd >/dev/null 2>&1; then
  # Validate/reload only when SSH daemon is currently active. On fresh systems
  # sshd binary can exist without host keys, and `sshd -t` would fail.
  if [[ -n "${SSH_SERVICE}" ]]; then
    if ! sshd -t; then
      echo "Error: sshd config validation failed after writing ${SSH_DENY_FILE}." >&2
      exit 1
    fi
    systemctl reload "${SSH_SERVICE}"
  else
    echo "Warning: SSH service is not active; deny file was created but validation/reload was skipped." >&2
  fi
else
  echo "Warning: sshd not found; SSH deny file created but daemon was not validated/reloaded." >&2
fi

echo "Done."
echo "User: ${USERNAME}"
echo "Home: ${HOME_DIR}"
echo "SSH deny file: ${SSH_DENY_FILE}"
echo "Switch user from root/sudo: sudo -iu ${USERNAME}"
