# ai-workspace

Workspace for Python (`uv`), Node.js / TypeScript (`npm` + `tsx`), and Google Workspace automation (`gdrive`, `gdocs`, `gsheets`, `gslides`, `gcalendar`).

## Environment Setup

Cloud environments automatically bootstrap dependencies using [`.agents/environment.json`](.agents/environment.json).

To set up locally:

```bash
# Python (uv)
uv sync

# Node.js / TypeScript
npm ci
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

## Project Skills

- [`.agents/skills/google-workspace-workflows/SKILL.md`](.agents/skills/google-workspace-workflows/SKILL.md) — Multi-tool orchestration guidelines and safety guardrails across Google Drive, Docs, Sheets, Slides, and Calendar.
