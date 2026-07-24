# <Service> skill — credentials setup

This skill reads its credentials from environment variables, auto-sourced from
the **project root `.env`** (gitignored), then a skill-local `.env` if present
(local overrides root). Fill the root `.env` — no manual export needed.
**Never commit the filled-in `.env`.**

## Prerequisites

- **`curl`** — ships with macOS/Linux (and Windows 10+).
- **`node`** (Node.js) — powers response summarisation, the reason this skill
  costs far less context than the MCP. It runs on Windows/macOS/Linux and is
  usually already installed for dev work. Without it the script still runs (and
  prints a warning) but returns **raw, unsummarised payloads**. No other tool is
  needed — URL-encoding is pure bash.

## Steps

1. Add the block below to the project root `.env` (create the file if absent).
2. Fill in the values (see where to get each, below).
3. Confirm `.env` is gitignored: `git check-ignore .env` should print `.env`.

```bash
# --- <Service> skill credentials ---

# <SERVICE>_TOKEN: <where to generate it, e.g. https://service.com/settings/tokens>
<SERVICE>_TOKEN=

# <SERVICE>_KEY: <only if the service uses key+token, e.g. Trello>
# <SERVICE>_KEY=
```

## Variables

| Var | Required | Where to get it |
|---|---|---|
| `<SERVICE>_TOKEN` | yes | <link + any scope note, e.g. grant read/write> |
| `<SERVICE>_KEY` | <yes/no> | <link, only if applicable> |

## Security

- The token grants access to your <Service> account. Treat it like a password.
- The script passes the token to `curl` via a stdin config (`-K -`), so it does
  **not** appear in `ps` output or shell history.
- If a token is ever exposed (logs, screen share, a pasted URL), revoke it at
  <revoke URL> and generate a new one.
