#!/usr/bin/env bash

set -euo pipefail

LOCAL_HOME="${1:-}"

# REMARKS: ホームディレクトリにホストコンピューターと同等のパスで `.claude` を配置するためのシンボリックリンクを作成する。
if [[ -n "${LOCAL_HOME}" && "${LOCAL_HOME}" != "${HOME}" ]]; then
  sudo mkdir -p "${LOCAL_HOME}"
  sudo ln -sfn "${HOME}/.claude" "${LOCAL_HOME}/.claude"
fi

# REMARKS: difftastic を diff コマンドの代替として使用するためのエイリアスを設定する。
sudo git config --system alias.dft '-c diff.external="difft --color always" -c pager.diff=false diff'

UV_LINK_MODE=copy uv sync --frozen
pnpm install --frozen-lockfile
