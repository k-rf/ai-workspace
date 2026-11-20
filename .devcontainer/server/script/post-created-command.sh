#!/usr/bin/env bash

set -euo pipefail

LOCAL_HOME="${1:-}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SHARED_SCRIPT_DIR=$(cd "${SCRIPT_DIR}/../../script" && pwd)

mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"

if [[ -n "${SSH_PUB_KEY:-}" && "${SSH_PUB_KEY}" != "<Your SSH public key>" ]]; then
  AUTH_KEYS="${HOME}/.ssh/authorized_keys"
  touch "${AUTH_KEYS}"
  chmod 600 "${AUTH_KEYS}"
  if ! grep -qxF "${SSH_PUB_KEY}" "${AUTH_KEYS}"; then
    printf '%s\n' "${SSH_PUB_KEY}" >> "${AUTH_KEYS}"
  fi
fi

"${SHARED_SCRIPT_DIR}/post-created-command.sh" "${LOCAL_HOME}"
