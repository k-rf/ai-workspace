# ai-workspace

Python（`uv`）、Node.js / TypeScript（`pnpm` + `tsx`）、Google Workspace 自動化（`gdrive`, `gdocs`, `gsheets`, `gslides`, `gcalendar`）、Notion（`ntn`）、Linear（`linearis`）向けのワークスペースです。

## 環境セットアップ

クラウド環境では [`.agents/environment.json`](.agents/environment.json) から [`.agents/install.sh`](.agents/install.sh) が自動実行され、依存パッケージの同期、`ntn`・`linearis` のグローバルインストール（`$PNPM_HOME/bin` への配置と `PATH` 設定）、`.agents/skills/` の `$HOME/.agents/skills/` への反映を行います。

ローカル環境でセットアップする場合：

```bash
# まとめてセットアップする場合
bash .agents/install.sh

# または個別にセットアップする場合
uv sync
pnpm install --frozen-lockfile
pnpm add -g --allow-build=ntn ntn linearis

# 任意: Notion / Linear トークンを .env に設定（gitignore 対象）
cp .env.example .env
```

> [!NOTE]
> Node.js 依存の `esbuild` およびグローバル CLI の `ntn` はインストール時スクリプトを使用するため、[`pnpm-workspace.yaml`](pnpm-workspace.yaml)（`allowBuilds: esbuild: true`）および `--allow-build=ntn` でビルド実行を許可しています。

### Dev Container（`editor` / `server`）

Docker 環境では [`editor`](.devcontainer/editor/devcontainer.json) と [`server`](.devcontainer/server/devcontainer.json) の 2 つの Dev Container 構成を利用できます（コンテナ内では Node.js 24・`pnpm`・`uv`・`ntn`・`linearis`・`ghealth`・各 AI エージェント CLI がビルド時に導入され、コンテナ作成時は `uv sync --frozen` と `pnpm install --frozen-lockfile` を実行します。クラウド環境向けの [`.agents/install.sh`](.agents/install.sh) とは独立しています）。

- **`editor`**（`.devcontainer/editor/`）: Cursor / VS Code から開くハーネス整備・スクリプト編集用コンテナです。
- **`server`**（`.devcontainer/server/`）: 常駐サーバー用コンテナです（`devstone-server` と同時稼働できるようポートを割り当てています）。
  - SSH (`sshd`): ホスト `2223` -> コンテナ `2222`
  - T3 Code (`t3 serve`): ホスト `3774` -> コンテナ `3774`
  - Orca (`orca serve`): ホスト `6770` -> コンテナ `6770`
- **環境変数の設定**: 初回起動時に `.devcontainer/.env.local.example` から `.devcontainer/.env.local`（gitignore 対象）が自動生成されます。`SSH_PUB_KEY`、`ORCA_PAIRING_ADDRESS`、`OP_SERVICE_ACCOUNT_TOKEN`、および各種 API トークンを設定してください。

## よく使うコマンド

### Python

```bash
uv run ruff check .  # Linter を実行
```

### TypeScript / Node.js

```bash
pnpm exec tsx <script.ts>   # スクリプトを実行
```

### Notion（`ntn`）および Linear（`linearis`）CLI

両 CLI は [`.agents/install.sh`](.agents/install.sh) によって `pnpm` でグローバルインストールされます（標準配置先: `$PNPM_HOME/bin/ntn`、`~/.local/share/pnpm/bin/linearis` 等）。

#### Notion（`ntn`）

```bash
# ボディを標準入力から渡さない場合、非対話シェルでの待機を防ぐため `< /dev/null` を付ける
ntn whoami --json < /dev/null
ntn api ls --plain < /dev/null
ntn api v1/search query="Roadmap" page_size:=10 < /dev/null
```

- **推奨認証（ヘッドレス／エージェント実行）**: `.env` または環境変数に `NOTION_API_TOKEN` を設定します（`ntn pages` コマンド群の利用にも必須です）。
- **ヘッドレス OAuth での代替認証**: OS キーリングのない Linux 環境では `NOTION_KEYRING=0` を指定します。
  ```bash
  NOTION_KEYRING=0 ntn login --no-browser < /dev/null
  NOTION_KEYRING=0 ntn login poll < /dev/null
  ```
  （Antigravity Remote Agents の別会話へ認証状態を引き継ぎたい場合は `NOTION_HOME="$HOME/.gemini/notion"` を設定できます。ただし `~/.gemini` は同一ユーザーの会話間で共有されます。）

#### Linear（`linearis` / `linear`）

```bash
linearis auth status            # {"authenticated": true|false} を確認
linearis usage                  # 全ドメインのコンパクト概要を表示
linearis issues usage           # issues ドメインの詳細リファレンスを表示
linearis issues list --limit 10
```

- **推奨認証（ヘッドレス／エージェント実行）**: `.env` または環境変数に `LINEAR_API_TOKEN` を設定します（`linearis auth login` は人間向けの対話フローで `~/.linearis/token` へ保存します）。

#### Remote Agents のネットワーク許可ホスト

Turbo モード以外で利用する場合は、以下のホストへのアウトバウンド HTTPS 通信を許可してください。

- Notion: `api.notion.com`（MCP 利用時は `mcp.notion.com`、`ntn api` の OpenAPI 探索を使う場合は `developers.notion.com` も）
- Linear: `api.linear.app`
- Toggl Track: `focus.toggl.com`（MCP 利用時）

### MCP サーバー

[`.agents/mcp_config.json`](.agents/mcp_config.json) に以下の公式リモート MCP サーバーを設定しています。

- **設定済みサーバー**:
  - `notion`: `https://mcp.notion.com/mcp`
  - `toggl`: `https://focus.toggl.com/mcp`
- **初回認証**: Antigravity の MCP 設定画面または CLI の `/mcp` から OAuth 認証を行ってください。
- **ヘッドレス環境**: Remote Agents 等でブラウザ OAuth が使えない場合は、上記の `ntn` CLI（`NOTION_API_TOKEN`）など CLI ベースの連携を使用します。

## プロジェクトスキル

- [`.agents/skills/google-workspace-workflows/SKILL.md`](.agents/skills/google-workspace-workflows/SKILL.md) — Google Drive / Docs / Sheets / Slides / Calendar を横断する自動化手順と安全ガードレール
- [`.agents/skills/notion-cli/SKILL.md`](.agents/skills/notion-cli/SKILL.md) — `ntn` を使った Notion のページ・データソース・ブロック・API 操作ガイド
- [`.agents/skills/linear-cli/SKILL.md`](.agents/skills/linear-cli/SKILL.md) — `linearis` を使った Linear の Issue・議論スレッド・プロジェクト・一括操作ガイド
- [`.agents/skills/ghealth-vitals/SKILL.md`](.agents/skills/ghealth-vitals/SKILL.md) — `ghealth` を使った Google Health API のバイタル情報取得・集計ガイド
