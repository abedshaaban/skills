# Trello skill — credentials setup

This skill reads its credentials from environment variables, auto-sourced from
the **project root `.env`** (resolved via `git rev-parse`, gitignored), then a
skill-local `.env` if present (local overrides root). Fill the root `.env` — no
manual export needed. **Never commit the filled-in `.env`.**

## Prerequisites

- **`bash` 3.2 or newer** — the version macOS still ships as `/bin/bash`, so no
  upgrade is needed anywhere.
- **`curl`** — ships with macOS/Linux (and Windows 10+).
- **`node`** (Node.js) — powers response summarisation, the reason this skill
  costs far less context than the MCP. It runs on Windows/macOS/Linux and is
  usually already installed for dev work, so there's normally nothing to add.
  Without it the script still runs (and prints a warning) but returns **raw,
  unsummarised payloads**. No other tool is needed — URL-encoding is pure bash.

## Steps

1. Add the block below to your project-root `.env` (create the file if absent).
2. Fill in the values (see where to get each, below).
3. Confirm `.env` is gitignored: `git check-ignore .env` should print `.env`.

```bash
# --- Trello skill credentials ---

# TRELLO_API_KEY: generate at https://trello.com/power-ups/admin  (legacy: https://trello.com/app-key)
TRELLO_API_KEY=

# TRELLO_TOKEN: generate from the same page using the API key above (grant read/write scope)
TRELLO_TOKEN=

# TRELLO_BOARD_ID: optional default board for board-scoped commands (mirrors the MCP "active board").
# Get it from `list-boards` output, or the board URL: https://trello.com/b/<TRELLO_BOARD_ID>/...
# TRELLO_BOARD_ID=
```

## Variables

| Var | Required | Where to get it |
|---|---|---|
| `TRELLO_API_KEY` | yes | https://trello.com/power-ups/admin (or legacy https://trello.com/app-key) |
| `TRELLO_TOKEN` | yes | Same page, generated from the API key. Grant **read/write** scope. |
| `TRELLO_BOARD_ID` | no | Default board for board-scoped commands when you omit the id. From `list-boards` or a board URL. |
| `TRELLO_YES` | no | Set in the **environment** to confirm a write/delete without a prompt. Required for every non-interactive run (see below). Ignored if set in `.env`. |

## Confirming writes

Commands that change data ask `Proceed? [y/N]` on an interactive terminal
(60-second timeout, and no answer means no change), and **refuse** when there is
no TTY — agents, scripts, CI. Pass `TRELLO_YES=1` per command to confirm:

```bash
TRELLO_YES=1 ./scripts/trello.sh archive-card 64card789
```

`TRELLO_YES` is deliberately honoured **only from the real environment**: a value
found in `.env` is ignored, and the prompt says so. Credentials belong in that
file because they are stable; standing consent does not, since one stray line
would disable every confirmation from then on.

## Security

- The `TRELLO_TOKEN` grants read/write to your Trello. Treat it like a password.
- The script passes the token to `curl` via a stdin config (`-K -`), so it does
  **not** appear in `ps` output or shell history.
- Attachment downloads must send the token as an `Authorization: OAuth` header
  (the attachment host rejects query-string auth). That header goes only to
  Trello hosts, and redirects are not followed, so an attachment URL coming back
  from the API cannot redirect the credentials to a third party.
- If a token is ever exposed (logs, screen share, a pasted URL), revoke it at
  https://trello.com/power-ups/admin and generate a new one.
