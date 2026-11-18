---
name: notion-cli
description: Read, search, create, update, and manage Notion pages, databases/data sources, blocks, comments, and file uploads via the `ntn` CLI in ai-workspace. Use when the user shares a notion.so / notion.site URL or asks to query Notion databases, read/edit Notion pages, search Notion content, or call the Notion API.
---
# Notion CLI (`ntn`)

Operate Notion workspaces from the terminal via the official `ntn` CLI (`@notionhq/ntn`, installed in `ai-workspace/node_modules/.bin/ntn`).

## 1. Pre-Flight: Binary, Stdin & Authentication

1. **Locate the binary**:
   - Prefer `ntn` on `PATH` (symlinked into `$HOME/.local/bin/ntn` by `.agents/environment.json`), or invoke `./node_modules/.bin/ntn` from the repo root (fallback: `npx --no-install ntn`).
2. **CRITICAL — Always redirect stdin (`< /dev/null`) when not piping a body**:
   - In non-interactive shells, `ntn` checks whether stdin is non-TTY and waits indefinitely for an implicit JSON body unless stdin reaches EOF or `--data` / `--filter-file -` / `< file` is explicitly used.
   - **Always append `< /dev/null`** to `ntn whoami`, `ntn doctor`, `ntn api ...` (without `-d @-`), `ntn pages get`, `ntn pages create --content ...`, `ntn pages edit --content ...`, and `ntn datasources ...` (without `--filter-file -`).
3. **Load local env cleanly (without printing secrets)** if `.env` is present:
   ```bash
   set -a; [ -f .env ] && . ./.env; set +a
   ```
4. **Verify authentication before workspace calls**:
   ```bash
   ntn whoami --json < /dev/null
   ```
   - `ntn doctor < /dev/null` prints configuration/health checks (exits `0` even with warnings — inspect output lines rather than relying on exit code alone).
   - **Recommended for Remote Agents / automation**: Set `NOTION_API_TOKEN` in the environment or gitignored `.env`. Integration tokens work without a browser or OS keyring, and **`ntn pages` commands currently require `NOTION_API_TOKEN`**.
   - **Headless OAuth alternative** (requires full workspace member role): Linux cloud VMs lack an OS keyring, so pass `NOTION_KEYRING=0`:
     1. Run `NOTION_KEYRING=0 ntn login --no-browser < /dev/null` to generate a URL + verification code.
     2. Ask the user to authorize in their browser and confirm the code matches.
     3. Redeem with `NOTION_KEYRING=0 ntn login poll < /dev/null`.
     - Optionally set `NOTION_HOME="$HOME/.gemini/notion"` if persistence across Remote Agent sessions is wanted (note `~/.gemini` is shared across Remote Agent conversations for the same user).
   - **Remote Agents network allowlist**: Outside Turbo mode, `api.notion.com` (and `developers.notion.com` if refreshing `ntn api` OpenAPI cache) must be allowed.

## 2. Discovery-First API Workflow

Inspect supported Notion endpoints and schemas before constructing requests:

```bash
# List public API endpoints (uses live or cached OpenAPI spec; no token required)
ntn api ls --plain < /dev/null

# Inspect schema or full Markdown documentation for a specific endpoint
ntn api v1/search --spec -X POST < /dev/null
ntn api v1/pages --docs -X POST < /dev/null
```

> [!NOTE]
> Avoid piping `ntn api ls` directly to `head` — closing stdout early can trigger a Rust broken-pipe panic. Filter with `grep` or inspect output cleanly instead.

Search Notion pages and data sources by title:

```bash
ntn api v1/search query="Project Plan" page_size:=10 < /dev/null
```

## 3. Common Operations

### A. Databases & Data Sources (API 2025-09-03+)

Databases can contain multiple data sources. Resolve a database ID before querying if uncertain:

```bash
# List data source IDs inside a database
ntn datasources resolve DATABASE_ID --json < /dev/null

# Query by data source ID, single-source database ID, or Notion URL
ntn datasources query ID_OR_URL --limit 25 --json < /dev/null
ntn datasources query ID_OR_URL -s "Updated desc" \
  --filter '{"property":"Status","status":{"equals":"In Progress"}}' --json < /dev/null
```

For large or nested filters, write JSON to `/tmp/notion-filter.json` and run `ntn datasources query ID_OR_URL --filter-file /tmp/notion-filter.json --json < /dev/null`.

### B. Reading & Writing Pages as Markdown (`ntn pages`)

`ntn pages` requires `NOTION_API_TOKEN`:

```bash
# Read page Markdown (includes YAML frontmatter with page properties)
ntn pages get PAGE_ID < /dev/null
# If stderr warns about truncated Markdown, inspect unknown_block_ids via --json:
ntn pages get PAGE_ID --json < /dev/null

# Create a page (parent format: page:<id>, database:<id>, or data-source:<id>)
ntn pages create --parent data-source:DATA_SOURCE_ID --content '# Title\n\nBody' --json < /dev/null
ntn pages create --parent page:PARENT_ID < /tmp/page.md

# Replace page Markdown content (leading frontmatter is stripped automatically)
ntn pages edit PAGE_ID --content '# Updated Title\n\nBody' --json < /dev/null
ntn pages edit PAGE_ID < /tmp/updated.md
```

### C. Structured Properties, Blocks & Comments (`ntn api`)

Use `ntn api` for database item properties, appending blocks without overwriting the whole page, comments, or moving pages:

- **Inline input syntax** (`:=` typed JSON, `=` string, `==` query param, `:` header):
  - `ntn api v1/blocks/PAGE_ID/children page_size:=50 < /dev/null` (`GET`)
  - `ntn api v1/comments block_id==PAGE_ID < /dev/null` (`GET`)
- **File payload syntax** (preferred for nested objects — keep temp files in `/tmp/`):
  - Append blocks: `ntn api v1/blocks/PAGE_ID/children -X PATCH -d @/tmp/blocks.json < /dev/null`
  - Update properties: `ntn api v1/pages/PAGE_ID -X PATCH -d @/tmp/props.json < /dev/null`
  - Create page with properties: `ntn api v1/pages -d @/tmp/new-page.json < /dev/null`

### D. File Uploads (`ntn files`)

```bash
ntn files create --filename report.pdf --content-type application/pdf < /tmp/report.pdf
ntn files create --external-url https://example.com/asset.png < /dev/null
ntn files list < /dev/null
```

## 4. Safety Guardrails

- **Read before writing**: Inspect target page content or database/data-source properties (`ntn api v1/data_sources/ID < /dev/null`) before creating or updating records.
- **Protect existing blocks**: `ntn pages edit` replaces page Markdown content and refuses to delete child pages/databases without `--allow-deleting-content`. When appending sections or editing pages with rich unsupported blocks, use `ntn api v1/blocks/<id>/children -X PATCH` instead.
- **No unrequested destructive actions**: Never run `ntn pages trash --yes`, `ntn pages edit --allow-deleting-content`, `ntn api ... -X DELETE`, or `ntn workers delete` unless the user explicitly asks for that deletion.
- **Secret & workspace hygiene**: Never run `ntn auth token` or `--unsafe-verbose` into logs or chat output, never commit tokens, and keep temporary JSON/Markdown files in `/tmp/`.
