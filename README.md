# ai-workspace

Workspace for Python (`uv`), Node.js / TypeScript (`npm` + `tsx`), Google Workspace automation (`gdrive`, `gdocs`, `gsheets`, `gslides`, `gcalendar`), Notion (`ntn`), and Linear (`linearis`).

## Environment Setup

Cloud environments automatically bootstrap dependencies using [`.agents/environment.json`](.agents/environment.json) (including `UV_SYSTEM_CERTS=true` for proxy TLS trust, `~/.local/bin` symlinks for repo CLIs, and syncing `.agents/skills/` into `$HOME/.agents/skills/`).

To set up locally:

```bash
# Python (uv)
uv sync

# Node.js / TypeScript + Notion / Linear CLIs
npm ci

# Optional: configure Notion / Linear tokens in gitignored .env
cp .env.example .env
```

## Common Commands

### Python

```bash
uv run pytest        # Run test suite
uv run ruff check .  # Run linter
```

### TypeScript / Node.js

```bash
npm run typecheck    # Type-check with tsc --noEmit
npm run build        # Compile TypeScript to dist/
npm start            # Run src/index.ts with tsx
```

### Notion (`ntn`) & Linear (`linearis`) CLIs

Both CLIs are installed via `npm ci` (`./node_modules/.bin/ntn` and `./node_modules/.bin/linearis`, and symlinked into `~/.local/bin` by `.agents/environment.json`).

#### Notion (`ntn`)

```bash
# Non-interactive commands require `< /dev/null` when not piping a JSON body
ntn whoami --json < /dev/null
ntn api ls --plain < /dev/null
ntn api v1/search query="Roadmap" page_size:=10 < /dev/null
```

- **Recommended auth (headless / agents)**: Set `NOTION_API_TOKEN` in `.env` or environment variables (also required for `ntn pages` commands).
- **Headless OAuth alternative**: On Linux without an OS keyring, pass `NOTION_KEYRING=0`:
  ```bash
  NOTION_KEYRING=0 ntn login --no-browser < /dev/null
  NOTION_KEYRING=0 ntn login poll < /dev/null
  ```
  (Set `NOTION_HOME="$HOME/.gemini/notion"` if you want auth state persisted across Antigravity Remote Agent conversations; note `~/.gemini` is shared across conversations for the same user.)

#### Linear (`linearis` / `linear`)

```bash
linearis auth status            # Inspect {"authenticated": true|false}
linearis usage                  # Compact overview of all domains
linearis issues usage           # Full reference for the issues domain
linearis issues list --limit 10
```

- **Recommended auth (headless / agents)**: Set `LINEAR_API_TOKEN` in `.env` or environment variables (`linearis auth login` is interactive for local use and writes `~/.linearis/token`).

#### Remote Agents Network Allowlist

Outside Turbo mode, allow outbound HTTPS access to:
- Notion: `api.notion.com` (and `developers.notion.com` for `ntn api` OpenAPI discovery)
- Linear: `api.linear.app`

## Project Skills

- [`.agents/skills/google-workspace-workflows/SKILL.md`](.agents/skills/google-workspace-workflows/SKILL.md) — Multi-tool orchestration guidelines and safety guardrails across Google Drive, Docs, Sheets, Slides, and Calendar.
- [`.agents/skills/notion-cli/SKILL.md`](.agents/skills/notion-cli/SKILL.md) — Notion page, database/data source, block, comment, and API workflows using `ntn`.
- [`.agents/skills/linear-cli/SKILL.md`](.agents/skills/linear-cli/SKILL.md) — Linear issue, discussion thread, project, cycle, document, and batch workflows using `linearis`.
