---
name: trello
description: Query Trello directly via REST curl instead of the mcp-server-trello MCP server. Use when the user wants to read or write Trello data — boards, lists, cards, comments, checklists, attachments, custom fields, activity — without loading the Trello MCP into context. Trigger whenever the user mentions Trello and wants data listed, a card/list/comment read or created/moved/archived, or a checklist item toggled, even if they don't say "skill".
---

# Trello (direct REST)

Wraps the Trello REST API (`https://api.trello.com/1`) as one dispatcher script, so operations cost nothing in context until run. Prefer this over the `mcp-server-trello` MCP for the operations below.

## Setup

Requires these environment variables (full setup in [SETUP.md](SETUP.md)):

- `TRELLO_API_KEY` — from https://trello.com/power-ups/admin (or https://trello.com/app-key)
- `TRELLO_TOKEN` — generate from the same page using the API key
- `TRELLO_BOARD_ID` — optional. When set, board-scoped commands use it if you omit the board id (mirrors the MCP's "active board").

The script auto-sources these from the **project root `.env`** (resolved via `git rev-parse`, gitignored), then a skill-local `.env` if present (local overrides root). Fill the root `.env` — no need to export manually. Never commit it.

## Commands

Run: `./scripts/trello.sh <command> [args...]`

| Command | Args | When to use |
|---|---|---|
| `list-boards` | — | All boards you can access |
| `board-info` | `[boardId]` | Detail for one board (defaults to `TRELLO_BOARD_ID`) |
| `list-workspaces` | — | All workspaces/orgs you can access |
| `boards-in-workspace` | `<workspaceId>` | Boards inside a workspace |
| `get-lists` | `[boardId]` | Lists on a board |
| `add-list` | `"<name>" [boardId]` | Create a list (write) |
| `archive-list` | `<listId>` | Archive a list (write) |
| `update-list` | `<listId> <query>` | Rename/move/close a list, e.g. `name=Done` / `pos=top` / `closed=true` (write) |
| `get-card` | `<cardId>` | Full card detail incl. custom-field items **and attachments** |
| `cards-in-list` | `<listId>` | Cards in a list |
| `my-cards` | — | Cards assigned to you |
| `add-card` | `<listId> "<name>" ["<desc>"]` | Create a card (write) |
| `update-card` | `<cardId> <query>` | Edit card, e.g. `name=New` / `dueComplete=true` / `desc=...` (write) |
| `move-card` | `<cardId> <listId>` | Move card to another list (write) |
| `archive-card` | `<cardId>` | Archive a card (write) |
| `card-comments` | `<cardId> [limit]` | Comments on a card |
| `add-comment` | `<cardId> "<text>"` | Comment on a card (write) |
| `update-comment` | `<commentId> "<text>"` | Edit a comment (write) |
| `delete-comment` | `<commentId>` | Delete a comment (destructive) |
| `board-checklists` | `[boardId]` | All checklists + items on a board (filter by name in output) |
| `card-checklists` | `<cardId>` | Checklists + items on one card (gives checklist ids) |
| `add-checklist-item` | `<checklistId> "<text>"` | Add an item to a checklist (write) |
| `update-checklist-item` | `<cardId> <checkItemId> <query>` | Toggle/rename item, e.g. `state=complete` (write) |
| `delete-checklist-item` | `<cardId> <checkItemId>` | Remove a checklist item (destructive) |
| `card-attachments` | `<cardId>` | Attachments on a card (ids, names, sizes, download + preview URLs) |
| `download-attachment` | `<cardId> <attachmentId> [outPath]` | Download one attachment to disk (auth handled) |
| `download-card-attachments` | `<cardId> [dir]` | Download every attachment on a card |
| `download-url` | `<trelloUrl> [outPath]` | Download any Trello attachment/preview URL, e.g. an `![img](...)` link inside a card desc |
| `attach-url` | `<cardId> <url> ["<name>"]` | Attach an image/file by URL (write) |
| `board-custom-fields` | `[boardId]` | Custom-field definitions on a board |
| `recent-activity` | `[boardId] [limit]` | Recent board activity |
| `help` | — | Print all commands |

## Confirmation gate on writes

Write commands (`add-*`, `update-*`, `move-*`, `archive-*`, `attach-*`) and the
irreversible `delete-*` ones change someone's real board, so they do not just run:

- **Interactive terminal** → prints `About to …` and asks `Proceed? [y/N]`;
  anything but `y`/`yes` aborts without sending a request. The prompt times out
  after 60s (so an unattended terminal can't block forever) and a timeout, an
  empty answer, or closed input all mean *no change*.
- **Non-interactive** (agent, script, CI — no TTY) → **refuses** and exits 1.
  Re-run with `TRELLO_YES=1` to state intent:

```bash
TRELLO_YES=1 ./scripts/trello.sh move-card 64card789 64otherlist
```

Putting the flag in the command line keeps the intent visible in whatever is
approving that command — which is why `TRELLO_YES` is read from the environment
only and **ignored when set in `.env`**. Read commands and `download-*` are never
gated.

## Examples

```bash
./scripts/trello.sh list-boards
./scripts/trello.sh get-lists 64abc123
./scripts/trello.sh cards-in-list 64def456
./scripts/trello.sh add-card 64def456 "Fix staff confirmation modal" "reported by QA"
./scripts/trello.sh move-card 64card789 64otherlist
./scripts/trello.sh update-checklist-item 64card789 64item111 state=complete
```

## Attachments and images

`get-card` lists a card's attachments, and card descriptions/comments often embed
images as `![name](https://trello.com/1/cards/.../download/name.png)`.

**Those URLs are not public.** Fetching one with a plain GET — or with
`?key=…&token=…` in the query, which works everywhere else in the API — returns
`401 unauthorized`. The attachment host (`trello.com`, not `api.trello.com`)
accepts only an `Authorization: OAuth oauth_consumer_key="…", oauth_token="…"`
header. Use the `download-*` commands, which add that header for you; don't hand
a raw attachment URL to `WebFetch`/`curl` or to the user's browser-less tooling
and expect bytes back.

Downloads default to `./trello-attachments/<cardId>/`, with the attachment id
prefixed onto each filename (several attachments on one card are usually all
named `image.png`). Read the saved file to actually view the image.

```bash
./scripts/trello.sh card-attachments NLeXV6uN
./scripts/trello.sh download-card-attachments NLeXV6uN            # → ./trello-attachments/NLeXV6uN/
./scripts/trello.sh download-attachment NLeXV6uN 69f33331f10b84017bc4c734 shot.png
./scripts/trello.sh download-url "https://trello.com/1/cards/699e…/attachments/699e…/previews/699e…/download/image.webp"
```

Each attachment's `preview` URL is the largest generated preview (usually `.webp`,
smaller than the original) — good enough for reading a screenshot.

Behaviour worth knowing:

- The credential header goes **only** to `https://` Trello hosts, and redirects
  are not followed. Attachment URLs are untrusted input — a *link* attachment
  holds whatever URL someone typed — so a card cannot steer the token elsewhere.
- Link attachments pointing off-Trello are therefore skipped by
  `download-card-attachments`; it still downloads the rest, reports how many were
  skipped, and exits non-zero if any were.
- A download that fails leaves an existing file at `outPath` untouched (the fetch
  lands in a temp file and is moved into place only on success).

Free-form fields use `<query>` args in `key=value` form (Trello REST param names). Chain several with `&`, e.g. `update-card 64card789 'name=Renamed&due=2026-08-01T12:00:00Z'`. Values may contain spaces/specials — the value side is URL-encoded automatically, so pass plain text (`name=New Name`), not pre-encoded (`name=New%20Name`, which would double-encode). A literal `&` inside a `<query>` value isn't supported: it splits key=value pairs, and pre-encoding as `%26` just double-encodes (the value is always run through the encoder). For a value that must contain `&`, use a command that takes it as a positional argument (`add-card`, `add-comment`, `update-comment`), which encodes the whole value safely.

## Notes

- Every call prints `HTTP:<code>` to stderr (the body stays clean on stdout so it pipes into the summariser). `2xx` = success; `401/403` = check `TRELLO_API_KEY`/`TRELLO_TOKEN`; `404` = bad id/path. On any `>=400` the command exits non-zero and the error body goes to stderr (nothing on stdout), so failures are catchable by exit code.
- Dates: due dates use ISO 8601 with time (`2026-08-01T12:00:00Z`); start dates use `YYYY-MM-DD`.
- Rate limits: ~300 req/10s per key, ~100 req/10s per token — batch reads sensibly.
- Output is summarised via `node` (cross-platform, usually already installed — see [SETUP.md](SETUP.md)). If `node` is missing the script prints a warning and returns raw payloads; if the body isn't JSON the raw payload is printed. URL-encoding of names/queries is pure bash — no tool needed.
- Coverage: the common board/list/card/comment/checklist/attachment/custom-field/activity operations. Intentionally omitted: `set_active_board`/`set_active_workspace` (MCP-local state — use `TRELLO_BOARD_ID` instead).
