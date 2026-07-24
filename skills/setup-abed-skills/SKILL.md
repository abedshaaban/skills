---
name: setup-abed-skills
description: One-time setup for the skills installed from abedshaaban/skills. Run this after `npx skills@latest add abedshaaban/skills` to wire up credentials — it detects which of these skills are present (trello, un-mcp) and walks you through the project-root .env and prerequisites for each. Trigger with "/setup-abed-skills", "set up my skills", or right after installing them.
---

# Setup — abedshaaban/skills

Run this once per project after installing skills from `abedshaaban/skills`. It
gets the installed skills working: credentials in the project-root `.env`,
prerequisites checked, one read-only verification per skill.

## 1. Detect what's installed

Find the skills directory in this project (check in order, use the first that
exists): `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`. List which of
these skills are present:

- `trello` — needs Trello REST credentials.
- `un-mcp` — no credentials of its own (it *generates* skills); only needs `node`.

Only run the steps for skills that are actually installed. Report what you found.

## 2. Prerequisites

Both skills lean on two tools:

- **`curl`** — ships with macOS/Linux/Windows 10+. Confirm: `curl --version`.
- **`node`** — powers response summarisation (what makes these skills cheaper
  than a live MCP). Confirm: `node --version`. If missing, the scripts still run
  but return raw, unsummarised payloads — tell the user and point at the skill's
  `SETUP.md`.

## 3. Credentials → project-root `.env`

The scripts auto-source the **project-root `.env`** (resolved via
`git rev-parse --show-toplevel`, gitignored), then a skill-local `.env` if
present. Never export secrets by hand; never commit the filled `.env`.

First confirm `.env` is ignored — if `git check-ignore .env` prints nothing, add
`.env` to `.gitignore` before writing any secret.

### trello

Read [`trello/SETUP.md`](../trello/SETUP.md) and add this block to the
project-root `.env`:

```bash
# --- Trello skill credentials ---
TRELLO_API_KEY=      # https://trello.com/power-ups/admin (legacy: /app-key)
TRELLO_TOKEN=        # generate from the same page, grant read/write scope
# TRELLO_BOARD_ID=   # optional default board (from list-boards, or board URL)
```

Do **not** ask the user to paste raw tokens into chat — have them fill the
gitignored `.env` themselves. Entering the values is theirs to do.

## 4. Verify (read-only)

Once credentials are set, prove each skill works with one safe read:

- **trello** — `./skills/trello/scripts/trello.sh list-boards` (adjust the path
  to wherever it installed). Expect `HTTP:200` on stderr and a board list on
  stdout. `401/403` → check `TRELLO_API_KEY`/`TRELLO_TOKEN`. Never echo the token
  when reporting an auth error.
- **un-mcp** — nothing to verify; it runs on demand when you ask it to convert an
  API/MCP into a new skill.

## 5. Report

Say which skills were detected, which credentials are still blank, the verified
read command and its result, and — if `node` was missing — that responses will
be raw until it's installed.
