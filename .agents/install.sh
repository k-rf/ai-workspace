#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

append_bashrc_line() {
  local line="$1"
  local bashrc="${HOME}/.bashrc"
  touch "${bashrc}"
  grep -qxF "${line}" "${bashrc}" 2>/dev/null || printf '%s\n' "${line}" >> "${bashrc}"
}

can_write_npm_prefix() {
  local prefix="$1"
  local lib_dir="${prefix}/lib/node_modules"
  local bin_dir="${prefix}/bin"

  if [ -d "${lib_dir}" ]; then
    [ -w "${lib_dir}" ] || return 1
  elif [ -d "${prefix}/lib" ]; then
    [ -w "${prefix}/lib" ] || return 1
  else
    [ -w "${prefix}" ] || return 1
  fi

  if [ -d "${bin_dir}" ]; then
    [ -w "${bin_dir}" ] || return 1
  else
    [ -w "${prefix}" ] || return 1
  fi

  return 0
}

# Remove non-interactive early-return guard from ~/.bashrc so BASH_ENV picks up exports
sed -i '/case \$- in/,/esac/d' "${HOME}/.bashrc" 2>/dev/null || true

# Persist Python (uv) proxy TLS and overlayfs settings
append_bashrc_line 'export UV_LINK_MODE=copy'
append_bashrc_line 'export UV_SYSTEM_CERTS=true'

UV_SYSTEM_CERTS=true UV_LINK_MODE=copy uv sync

# Install repository Node.js / TypeScript dependencies
if [ -f package-lock.json ]; then
  npm ci --prefer-offline --no-audit --no-fund
else
  npm install --no-audit --no-fund
fi

# Install Notion (ntn) and Linear (linearis) CLIs globally.
# Fall back to ~/.local when the default global npm prefix is not writable (e.g. cloud VMs).
CURRENT_NPM_PREFIX="$(npm prefix -g)"
if ! can_write_npm_prefix "${CURRENT_NPM_PREFIX}"; then
  mkdir -p "${HOME}/.local"
  export NPM_CONFIG_PREFIX="${HOME}/.local"
  append_bashrc_line 'export NPM_CONFIG_PREFIX="$HOME/.local"'
  append_bashrc_line 'export PATH="$HOME/.local/bin:$PATH"'
elif [ "${CURRENT_NPM_PREFIX}" = "${HOME}/.local" ]; then
  mkdir -p "${HOME}/.local"
  append_bashrc_line 'export NPM_CONFIG_PREFIX="$HOME/.local"'
  append_bashrc_line 'export PATH="$HOME/.local/bin:$PATH"'
fi

npm install -g --prefer-offline --no-audit --no-fund ntn linearis

# Sync project skills to $HOME/.agents/skills/
if [ -d .agents/skills ]; then
  mkdir -p "${HOME}/.agents/skills"
  cp -R .agents/skills/. "${HOME}/.agents/skills/"
fi
