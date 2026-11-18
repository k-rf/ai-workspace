---
name: linear-cli
description: ai-workspace 環境で `linearis` CLI を使い、Linear の Issue、議論スレッド、プロジェクト、サイクル、マイルストーン、イニシアチブ、ドキュメント、添付ファイル、ラベル、チームの参照・検索・作成・更新を行う。ユーザーが linear.app の URL や `ENG-42` などの Issue キーを共有した場合、または Linear のタスク管理を依頼したときに使用する。
---
# Linear CLI (`linearis`)

AI エージェント向けに JSON 専用出力で設計された `linearis` CLI（別名 `linear`、グローバルインストール済み）を使って Linear ワークスペースを操作するためのスキルです。

## 1. 事前確認：バイナリと認証

1. **バイナリの確認**:
   - `PATH` 上の `linearis`（または `linear`）を使用します（`.agents/environment.json` → `.agents/install.sh` により `pnpm` でグローバルインストールされ、`$PNPM_HOME/bin/linearis`〔標準 `~/.local/share/pnpm/bin/linearis`〕に配置されます）。見つからない場合は `bash .agents/install.sh` を実行するか `"${PNPM_HOME:-$HOME/.local/share/pnpm}/bin/linearis"` を確認してください。
2. **ローカル `.env` の読み込み（トークンを出力しない）**:
   ```bash
   set -a; [ -f .env ] && . ./.env; set +a
   ```
3. **操作前に認証状態を確認する**:
   ```bash
   linearis auth status
   ```
   > [!IMPORTANT]
   > `linearis auth status` は未認証でも終了コード `0` を返します。終了コードではなく出力 JSON の `"authenticated": true` を確認してください。
   - **トークン解決の優先順位**: `--api-token <token>` フラグ → `LINEAR_API_TOKEN` 環境変数 → `~/.linearis/token`（暗号化保存）→ `~/.linear_api_token`（非推奨）。
   - **Remote Agents / 自動処理の推奨設定**: 環境変数または gitignore 済みの `.env` に `LINEAR_API_TOKEN` を設定してください（シェル履歴やプロセス引数に残る `--api-token` は避ける）。`linearis auth login` は人間向けの対話ログイン用です。
   - stderr の更新通知を抑止したい場合は `NO_UPDATE_NOTIFIER=1` を指定できます。
   - **Remote Agents ネットワーク許可設定**: Turbo モード以外で実行する場合、`api.linear.app` への送信を許可する必要があります。

## 2. 2段階の「探索 → 実行」ワークフロー

`linearis` は標準出力に **JSON のみ**、標準エラー出力に構造化エラー JSON を出力します。フラグを推測せず、必要なドメインのドキュメントだけオンデマンドで読み込みます。

```bash
# 1. 全ドメインの概要を取得（約 200 トークン）
linearis usage

# 2. 使用するドメインの詳細リファレンスのみ取得（約 300〜500 トークン）
linearis issues usage
linearis projects usage
linearis documents usage
```

大量の JSON 出力をそのままコンテキストに展開せず、`jq` や `uv run python ...` / `node` で必要なフィールドだけを抽出してください。

## 3. 主な操作パターンと仕様上の注意点

### A. Issue（`issues`）とスマート ID 解決

Issue キー（`ENG-42`）、チームキー／名称（`ENG`, `Platform`）、ユーザー名／メール／`me`、プロジェクト名、UUID をそのまま引数に渡せます。

```bash
# 未完了 Issue 一覧を取得（デフォルトで completed と archived は除外される）
linearis issues list --team ENG --limit 25

# archived を除いて完了済み Issue だけ見る場合／archived も含める場合
linearis issues list --team ENG --state-type completed --limit 25
linearis issues list --team ENG --include-archived --limit 25

# 全文検索（デフォルトで完了済み Issue も結果に含まれる）
linearis issues search "auth timeout" --limit 20

# 議論スレッドと添付ファイル付きで詳細取得
linearis issues read ENG-42 --with-comment-threads --with-attachments

# 現在の git ブランチに対応する Issue を検索
linearis issues from-branch
```

### B. 議論スレッド（非推奨 `comments` ではなく `discussions` 系を使用）

`linearis comments` は後方互換の非推奨ファサードです。`issues` / `projects` / `initiatives` 配下の議論コマンドを使用してください。

```bash
linearis issues discussions ENG-42
linearis issues replies THREAD_UUID
linearis issues discuss ENG-42 --body "原因調査の結果..."
linearis issues reply THREAD_UUID --body "追記です"   # 返信 ID ではなく必ずルートスレッド ID を指定
linearis issues resolve THREAD_UUID --with-comment COMMENT_UUID
```

### C. トランザクション一括作成／更新（`issues batch create` / `update`）

`issues batch create` と `issues batch update` は全件成功／全件ロールバックで実行され、未知の JSON キーは厳格に拒否されます。JSON Schema はグローバルインストール先パッケージ内に同梱されています（`find -L "$(pnpm root -g)" -path '*/linearis/schemas/*.schema.json'` で参照可能）：
- `issues-batch-create.schema.json`
- `issues-batch-update.schema.json`

ペイロードは `/tmp/` に保存・検証してから実行してください。

```bash
linearis issues batch create --file /tmp/issues-create.json
linearis issues batch update --file /tmp/issues-patch.json
```

`batch update` の `"patch"` 内でフィールド値に `null` を指定すると値がクリアされます（`--clear-*` 相当）。

### D. プロジェクト・マイルストーン・サイクル・ドキュメント・ファイル

- **プロジェクト**: `projects list|search|read|create|update`、健全性変更を伴う更新は `projects updates create --project ... --health onTrack|atRisk|offTrack --body "..."`、ゴミ箱移動／復元は `projects delete` / `unarchive`。
- **マイルストーン・ドキュメント**: `milestones list --project ...`、`documents list|read|create|update`。
- **サイクル（読み取り専用）**: `cycles list --team ENG --active`、`cycles read CYCLE`。
- **ファイル**: `linearis files download URL --output /tmp/attachment.bin`、`linearis files upload /tmp/file.png`（ダウンロード先はリポジトリ直下ではなく `/tmp/` に指定）。

## 4. 終了コードと対応範囲の境界

- **終了コード**: `0` = 成功（stdout に JSON）、`1` = アプリケーション／API エラー（`{"error": "..."}`）、`2` = 無効なコマンド指定（stderr の JSON に `suggestion`・`available_commands`・`instruction` を含む）、`42` = `AUTHENTICATION_REQUIRED`。
- **非対応領域**（`linearis` は日常的な Issue／プロジェクト運用向けで、管理系操作は未対応）: チームワークフロー状態の編集、組織／SSO／Webhook／外部連携設定、Releases、CRM（`customers`）、カスタムビュー、オンコールスケジュール、サイクルの作成／日程移動などは、Linear Web UI または `LINEAR_API_TOKEN` を用いた `https://api.linear.app/graphql` への直接 GraphQL リクエストで対応します。

## 5. 安全ガードレール

- **変更前に必ず現状確認**: フィールド更新やチーム間移動の前に、`linearis teams list`・`linearis labels list`・`linearis issues read ENG-42` で正しいチームキー・ステータス名・ラベル名を確認してください。
- **無断の破壊的・対外的変更を禁止**: ユーザーが明示的に指示または承認していない限り、`delete`・`archive`・`retire`、多数 Issue への一括 `batch update`、公開スレッドへの投稿（`discuss` / `reply`）、通知設定変更（`share` / `subscribe`）を実行しないでください。
- **秘密情報とリポジトリの保護**: `LINEAR_API_TOKEN` をログやコードに残さず（CLI 引数 `--api-token` より環境変数を使用）、一時 JSON やダウンロードファイルは `/tmp/` に保存してください。
