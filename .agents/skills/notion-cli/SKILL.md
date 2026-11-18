---
name: notion-cli
description: ai-workspace 環境で公式 `ntn` CLI を使い、Notion のページ、データベース／データソース、ブロック、コメント、ファイルアップロードの検索・取得・作成・更新を行う。ユーザーが notion.so / notion.site の URL を共有した場合や、Notion のデータベース照会・ページ読み書き・コンテンツ検索・API 呼び出しを依頼したときに使用する。
---
# Notion CLI (`ntn`)

公式 Notion CLI（`ntn`、グローバルインストール済み）を使ってターミナルから Notion ワークスペースを操作するためのスキルです。

## 1. 事前確認：バイナリ・標準入力・認証

1. **バイナリの確認**:
   - `PATH` 上の `ntn` を使用します（`.agents/environment.json` → `.agents/install.sh` によりグローバルインストールされ、クラウド環境では `$HOME/.local/bin/ntn` に配置されます）。見つからない場合は `bash .agents/install.sh` を実行するか `$HOME/.local/bin/ntn` を確認してください。
2. **【重要】ボディ入力を渡さないコマンドには必ず `< /dev/null` を付ける**:
   - `ntn` は非 TTY シェル（エージェント実行環境など）で標準入力が開いていると、暗黙の JSON リクエストボディを読み込もうとして無期限に待機する場合があります。
   - `--data` / `--filter-file -` / `< file` などで意図的に標準入力を渡す場合を除き、`ntn whoami`・`ntn doctor`・`ntn api ...`・`ntn pages get`・`ntn pages create --content ...`・`ntn pages edit --content ...`・`ntn datasources ...` には**必ず `< /dev/null` を付けてください**。
3. **ローカル `.env` の読み込み（トークンを出力しない）**:
   ```bash
   set -a; [ -f .env ] && . ./.env; set +a
   ```
4. **操作前に認証状態を確認する**:
   ```bash
   ntn whoami --json < /dev/null
   ```
   - `ntn doctor < /dev/null` は設定や接続状況の診断を表示します（警告があっても終了コード `0` を返すため、終了コードではなく出力内容を確認してください）。`ntn auth token` や `--unsafe-verbose` は認証情報を露出させるためログやチャットへ出力しないでください。
   - **Remote Agents / 自動処理の推奨設定**: 環境変数または gitignore 済みの `.env` に `NOTION_API_TOKEN` を設定します。インテグレーショントークンはブラウザや OS キーリング不要で動作し、**`ntn pages` コマンド群は現在 `NOTION_API_TOKEN` が必須**です。
   - **ヘッドレス OAuth での代替手順**（ワークスペースのフルメンバー権限が必要）: Linux クラウド VM には OS キーリングがないため `NOTION_KEYRING=0` を指定します。
     1. `NOTION_KEYRING=0 ntn login --no-browser < /dev/null` を実行し、表示された URL と確認コードをユーザーへ共有します。
     2. ユーザーにブラウザで承認し、確認コードの一致を確認してもらいます。
     3. `NOTION_KEYRING=0 ntn login poll < /dev/null` を実行してトークンを保存します。
     - Remote Agent の別セッションにも認証状態を引き継ぎたい場合は `NOTION_HOME="$HOME/.gemini/notion"` を設定できます（`~/.gemini` は同一ユーザーの Remote Agent 会話間で共有される点に留意してください）。
   - **Remote Agents ネットワーク許可設定**: Turbo モード以外で実行する場合、`api.notion.com`（および `ntn api` の OpenAPI 仕様キャッシュ取得時は `developers.notion.com`）への送信を許可する必要があります。

## 2. API 探索ファーストのワークフロー

パスやリクエスト形式を推測せず、まずライブ／キャッシュ済み OpenAPI 仕様を確認します。

```bash
# サポートされている公開 API エンドポイント一覧を表示（認証不要）
ntn api ls --plain < /dev/null

# 特定エンドポイントの縮小 OpenAPI スキーマまたは公式ドキュメントを表示
ntn api v1/search --spec -X POST < /dev/null
ntn api v1/pages --docs -X POST < /dev/null
```

> [!NOTE]
> `ntn api ls` の出力を直接 `head` へパイプすると標準出力クローズ時に Rust 側の broken pipe パニックが出るため、`grep` 等で絞り込むかそのまま参照してください。

ページやデータソースをタイトルで検索する例：

```bash
ntn api v1/search query="Project Plan" page_size:=10 < /dev/null
```

## 3. 主な操作パターン

### A. データベースとデータソース（API 2025-09-03 以降）

1 つのデータベースが複数のデータソースを持つ場合があります。データベース ID を扱う際は先にデータソース ID を解決してください。

```bash
# データベース ID に紐づくデータソース ID 一覧を取得
ntn datasources resolve DATABASE_ID --json < /dev/null

# データソース ID、単一ソースのデータベース ID、または Notion URL でクエリ
ntn datasources query ID_OR_URL --limit 25 --json < /dev/null
ntn datasources query ID_OR_URL -s "Updated desc" \
  --filter '{"property":"Status","status":{"equals":"In Progress"}}' --json < /dev/null
```

複雑なフィルタ条件は `/tmp/notion-filter.json` に書き出し、`ntn datasources query ID_OR_URL --filter-file /tmp/notion-filter.json --json < /dev/null` で渡します。

### B. Markdown としてのページ読み書き（`ntn pages`）

`ntn pages` を使う場合は `NOTION_API_TOKEN` の設定が必要です。

```bash
# ページを Markdown（先頭にプロパティのフロントマター付き）で取得
ntn pages get PAGE_ID < /dev/null
# stderr に省略・未知ブロックの案内が出た場合は --json で unknown_block_ids を確認
ntn pages get PAGE_ID --json < /dev/null

# ページ新規作成（--parent は page:<id> / database:<id> / data-source:<id>）
ntn pages create --parent data-source:DATA_SOURCE_ID --content '# Title\n\nBody' --json < /dev/null
ntn pages create --parent page:PARENT_ID < /tmp/page.md

# ページ本文の Markdown を更新（get 出力のフロントマターは自動で取り除かれる）
ntn pages edit PAGE_ID --content '# Updated Title\n\nBody' --json < /dev/null
ntn pages edit PAGE_ID < /tmp/updated.md
```

### C. 構造化プロパティ・ブロック・コメント操作（`ntn api`）

DB 項目のプロパティ更新、ページ全体を上書きしないブロック追記、コメント操作、ページ移動などは `ntn api` を使います。

- **インライン入力構文**（`:=` 型付き JSON、`=` 文字列、`==` クエリパラメータ、`:` ヘッダ）:
  - `ntn api v1/blocks/PAGE_ID/children page_size:=50 < /dev/null`（`GET`）
  - `ntn api v1/comments block_id==PAGE_ID < /dev/null`（`GET`）
- **JSON ファイル指定**（ネストした構造向け。一時ファイルは必ず `/tmp/` に置く）:
  - ブロック追記: `ntn api v1/blocks/PAGE_ID/children -X PATCH -d @/tmp/blocks.json < /dev/null`
  - プロパティ更新: `ntn api v1/pages/PAGE_ID -X PATCH -d @/tmp/props.json < /dev/null`
  - プロパティ付きページ作成: `ntn api v1/pages -d @/tmp/new-page.json < /dev/null`

### D. ファイルアップロード（`ntn files`）

```bash
ntn files create --filename report.pdf --content-type application/pdf < /tmp/report.pdf
ntn files create --external-url https://example.com/asset.png < /dev/null
ntn files list < /dev/null
```

## 4. 安全ガードレール

- **変更前に必ず読み取る**: ページやデータベース項目を作成・更新する前に、`ntn pages get` や `ntn api v1/data_sources/ID < /dev/null` で既存内容とプロパティ定義を確認してください。
- **既存コンテンツの保護**: `ntn pages edit` はページ本文全体を Markdown で置き換え、子ページ／子データベースの削除を伴う変更は `--allow-deleting-content` なしでは拒否されます。末尾への追記や複雑なブロックを保持したい場合は `ntn api v1/blocks/<id>/children -X PATCH` を使用してください。
- **無断の破壊的操作を禁止**: ユーザーが明示的に指示しない限り、`ntn pages trash --yes`・`ntn pages edit --allow-deleting-content`・`ntn api ... -X DELETE`・`ntn workers delete` を実行しないでください。
- **秘密情報とリポジトリの保護**: `NOTION_API_TOKEN` や `auth.json`、`ntn auth token`、`--unsafe-verbose` の出力を表示・コミットせず、一時ファイルは `/tmp/` にのみ作成してください。
