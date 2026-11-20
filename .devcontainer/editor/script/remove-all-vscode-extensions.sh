#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ENV_FILE="${SCRIPT_DIR}/../../.env"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

volume="${ROOT_VSCODE_EXTENSIONS_VOLUME_NAME:-ai-workspace-vscode-extensions}"
echo "Remove extensions in ${volume}"
docker run --rm -v "${volume}:/mnt/extensions" debian:trixie /bin/bash -c "find /mnt/extensions -mindepth 1 -delete"
