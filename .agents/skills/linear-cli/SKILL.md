---
name: linear-cli
description: Read, search, create, update, and manage Linear issues, discussion threads, projects, cycles, milestones, initiatives, documents, attachments, labels, and teams via the `linearis` CLI in ai-workspace. Use when the user shares a linear.app URL, references issue keys like ENG-42, or asks to manage Linear work items.
---
# Linear CLI (`linearis`)

Operate Linear workspaces via `linearis` (JSON-only CLI designed for AI agents, installed in `ai-workspace/node_modules/.bin/linearis`; `linear` is an identical alias).

## 1. Pre-Flight: Binary & Authentication

1. **Locate the binary**:
   - Prefer `linearis` on `PATH` (symlinked into `$HOME/.local/bin/linearis` by `.agents/environment.json`), or invoke `./node_modules/.bin/linearis` from the repo root (fallback: `npx --no-install linearis`).
2. **Load local env cleanly (without printing secrets)** if `.env` is present:
   ```bash
   set -a; [ -f .env ] && . ./.env; set +a
   ```
3. **Verify authentication before operations**:
   ```bash
   linearis auth status
   ```
   > [!IMPORTANT]
   > `linearis auth status` exits `0` even when unauthenticated — inspect the JSON field `"authenticated": true` rather than relying on exit code alone.
   - **Token resolution order**: `--api-token <token>` flag -> `LINEAR_API_TOKEN` env var -> `~/.linearis/token` (encrypted) -> `~/.linear_api_token` (deprecated).
   - **Recommended for Remote Agents / automation**: Set `LINEAR_API_TOKEN` in the environment or gitignored `.env` (prefer env vars over `--api-token` so tokens stay out of shell history and `ps` arguments). `linearis auth login` is an interactive flow for humans.
   - Pass `NO_UPDATE_NOTIFIER=1` if you need update check notices suppressed on stderr.
   - **Remote Agents network allowlist**: Outside Turbo mode, `api.linear.app` must be allowed.

## 2. Two-Tier Discover-Then-Act Workflow

`linearis` outputs **JSON only** on stdout and structured JSON errors on stderr. Load command references on demand rather than guessing flags:

```bash
# 1. Domain overview (~200 tokens)
linearis usage

# 2. Full reference for just the domain you need (~300-500 tokens)
linearis issues usage
linearis projects usage
linearis documents usage
```

Pipe large JSON results through `jq` or `uv run python ...` / `node` to extract only relevant fields.

## 3. Common Patterns & Domain Notes

### A. Issues (`issues`) & Smart IDs

Pass issue keys (`ENG-42`), team keys/names (`ENG`, `Platform`), user names/emails/`me`, project names, or UUIDs interchangeably where documented:

```bash
# List active/open issues (hides completed and archived by default)
linearis issues list --team ENG --limit 25

# Include completed work without archived issues, or include archived issues too
linearis issues list --team ENG --state-type completed --limit 25
linearis issues list --team ENG --include-archived --limit 25

# Full-text search (includes completed issues by default)
linearis issues search "auth timeout" --limit 20

# Read full details with discussion threads and attachments
linearis issues read ENG-42 --with-comment-threads --with-attachments

# Find issue matching current git branch
linearis issues from-branch
```

### B. Discussions (Prefer over Deprecated `comments`)

`linearis comments` is a deprecated compatibility facade. Use domain-scoped discussion commands on `issues`, `projects`, or `initiatives`:

```bash
linearis issues discussions ENG-42
linearis issues replies THREAD_UUID
linearis issues discuss ENG-42 --body "Root-cause analysis..."
linearis issues reply THREAD_UUID --body "Follow-up update"   # Always pass root thread ID, not reply ID
linearis issues resolve THREAD_UUID --with-comment COMMENT_UUID
```

### C. Transactional Batch Issue Operations

`issues batch create` and `issues batch update` execute all-or-nothing and strictly reject unknown JSON keys. JSON Schemas ship locally inside the installed package:
- `node_modules/linearis/schemas/issues-batch-create.schema.json`
- `node_modules/linearis/schemas/issues-batch-update.schema.json`

Write and validate batch payloads in `/tmp/` before running:

```bash
linearis issues batch create --file /tmp/issues-create.json
linearis issues batch update --file /tmp/issues-patch.json
```

In `batch update`, setting a key inside `"patch"` to `null` clears that field (equivalent to `--clear-*`).

### D. Projects, Milestones, Cycles, Documents & Files

- **Projects**: `projects list|search|read|create|update`, plus `projects updates create --project ... --health onTrack|atRisk|offTrack --body "..."` (project health derives from the latest status update) and `projects delete` / `unarchive`.
- **Milestones & Documents**: `milestones list --project ...`, `documents list|read|create|update`.
- **Cycles (read-only)**: `cycles list --team ENG --active`, `cycles read CYCLE`.
- **Files**: `linearis files download URL --output /tmp/attachment.bin` and `linearis files upload /tmp/file.png` (keep downloads in `/tmp/`, never repo root).

## 4. Exit Codes & Coverage Boundaries

- **Exit codes**: `0` = success (JSON stdout); `1` = application/API error (`{"error": "..."}`); `2` = invalid CLI invocation (stderr JSON includes `suggestion`, `available_commands`, `instruction`); `42` = `AUTHENTICATION_REQUIRED`.
- **Unsupported areas** (`linearis` covers day-to-day execution, not workspace administration): team workflow state editing, org/SSO/webhook/integration settings, releases, CRM (`customers`), custom views, on-call schedules, and cycle creation/shifting require Linear's Web UI or direct GraphQL requests to `https://api.linear.app/graphql` using `LINEAR_API_TOKEN`.

## 5. Safety Guardrails

- **Read before mutating**: Verify team keys, workflow status names (`linearis teams list`, existing issues), labels (`linearis labels list`), and current issue state (`linearis issues read ENG-42`) before modifying fields or moving issues across teams.
- **No unrequested destructive or noisy mutations**: Never run `delete`, `archive`, `retire`, large bulk `batch update`, public discussion replies (`discuss`/`reply`), or notification subscriptions (`share`/`subscribe`) unless explicitly intended or confirmed by the user.
- **Secret & repo hygiene**: Never commit or echo `LINEAR_API_TOKEN`, avoid passing `--api-token` directly on the CLI when env vars work, and direct downloads/temp JSON payloads to `/tmp/`.
