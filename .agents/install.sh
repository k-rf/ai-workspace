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

# Remove non-interactive early-return guard from ~/.bashrc so BASH_ENV picks up exports
sed -i '/case \$- in/,/esac/d' "${HOME}/.bashrc" 2>/dev/null || true

# Persist Python (uv) proxy TLS and overlayfs settings
append_bashrc_line 'export UV_LINK_MODE=copy'
append_bashrc_line 'export UV_SYSTEM_CERTS=true'

UV_SYSTEM_CERTS=true UV_LINK_MODE=copy uv sync

# Configure non-interactive Corepack & user-space pnpm global home
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export PNPM_HOME="${PNPM_HOME:-${HOME}/.local/share/pnpm}"
mkdir -p "${PNPM_HOME}/bin"
case ":${PATH}:" in
  *":${PNPM_HOME}/bin:"*) ;;
  *) export PATH="${PNPM_HOME}/bin:${PNPM_HOME}:${PATH}" ;;
esac

append_bashrc_line 'export COREPACK_ENABLE_DOWNLOAD_PROMPT=0'
append_bashrc_line 'export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"'
append_bashrc_line 'case ":$PATH:" in *":$PNPM_HOME/bin:"*) ;; *) export PATH="$PNPM_HOME/bin:$PNPM_HOME:$PATH" ;; esac'

# Install repository Node.js / TypeScript dependencies via pnpm
if [ -f pnpm-lock.yaml ]; then
  pnpm install --prefer-offline --frozen-lockfile
else
  pnpm install --prefer-offline --allow-build=esbuild
fi

# Install Notion (ntn) and Linear (linearis) CLIs globally via pnpm
pnpm add -g --prefer-offline --allow-build=ntn ntn linearis

# Sync project skills to $HOME/.agents/skills/
if [ -d .agents/skills ]; then
  mkdir -p "${HOME}/.agents/skills"
  cp -R .agents/skills/. "${HOME}/.agents/skills/"
fi
