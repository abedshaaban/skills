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
| `get-card` | `<cardId>` | Full card detail incl. custom-field items |
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
| `attach-url` | `<cardId> <url> ["<name>"]` | Attach an image/file by URL (write) |
| `board-custom-fields` | `[boardId]` | Custom-field definitions on a board |
| `recent-activity` | `[boardId] [limit]` | Recent board activity |
| `help` | — | Print all commands |

Write commands (`add-*`, `update-*`, `move-*`, `archive-*`, `attach-*`) change remote data and print what they will do first — confirm intent before running. `delete-*` is irreversible.

## Examples

```bash
./scripts/trello.sh list-boards
./scripts/trello.sh get-lists 64abc123
./scripts/trello.sh cards-in-list 64def456
./scripts/trello.sh add-card 64def456 "Fix staff confirmation modal" "reported by QA"
./scripts/trello.sh move-card 64card789 64otherlist
./scripts/trello.sh update-checklist-item 64card789 64item111 state=complete
```

Free-form fields use `<query>` args in `key=value` form (Trello REST param names). Chain several with `&`, e.g. `update-card 64card789 'name=Renamed&due=2026-08-01T12:00:00Z'`. Values may contain spaces/specials — the value side is URL-encoded automatically, so pass plain text (`name=New Name`), not pre-encoded (`name=New%20Name`, which would double-encode). A literal `&` inside a `<query>` value isn't supported: it splits key=value pairs, and pre-encoding as `%26` just double-encodes (the value is always run through the encoder). For a value that must contain `&`, use a command that takes it as a positional argument (`add-card`, `add-comment`, `update-comment`), which encodes the whole value safely.

## Notes

- Every call prints `HTTP:<code>` to stderr (the body stays clean on stdout so it pipes into the summariser). `2xx` = success; `401/403` = check `TRELLO_API_KEY`/`TRELLO_TOKEN`; `404` = bad id/path. On any `>=400` the command exits non-zero and the error body goes to stderr (nothing on stdout), so failures are catchable by exit code.
- Dates: due dates use ISO 8601 with time (`2026-08-01T12:00:00Z`); start dates use `YYYY-MM-DD`.
- Rate limits: ~300 req/10s per key, ~100 req/10s per token — batch reads sensibly.
- Output is summarised via `node` (cross-platform, usually already installed — see [SETUP.md](SETUP.md)). If `node` is missing the script prints a warning and returns raw payloads; if the body isn't JSON the raw payload is printed. URL-encoding of names/queries is pure bash — no tool needed.
- Coverage: the common board/list/card/comment/checklist/attachment/custom-field/activity operations. Intentionally omitted: `set_active_board`/`set_active_workspace` (MCP-local state — use `TRELLO_BOARD_ID` instead) and `download_attachment` (just GET the attachment URL from `get-card` directly).
