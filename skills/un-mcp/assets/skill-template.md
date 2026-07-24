---
name: <service>
description: Query <Service> directly via REST curl instead of the <Service> MCP server. Use when the user wants to <list/read/create> <Service> data (e.g. <boards, cards, issues>) without loading the MCP into context. Trigger whenever the user mentions <Service> and wants data read or a common write done, even if they don't say "skill".
---

# <Service> (direct REST)

Wraps the <Service> REST API as one dispatcher script so operations cost nothing in context until run. Prefer this over the <Service> MCP server for the operations below.

## Setup

Requires `node` (Node.js) for response summarisation — cross-platform and usually already installed; without it, reads return raw payloads. Plus these environment variables (full instructions in `SETUP.md`):

- `<SERVICE>_TOKEN` — <where to generate it>
- `<SERVICE>_KEY` — <if applicable>

Fill them into the gitignored project-root `.env`; the script auto-sources it. No manual export needed.

## Commands

Run: `./scripts/<service>.sh <command> [args...]`

| Command | Args | When to use |
|---|---|---|
| `list-<things>` | — | List all <things> you can access |
| `<things>-in-<parent>` | `<parentId>` | List <things> inside a <parent> |
| `get-<thing>` | `<id>` | Full detail for one <thing> |
| `create-<thing>` | `<parentId> "<name>"` | Create a <thing> (write) |
| `help` | — | Print all commands |

Write commands (`create-*`, `delete-*`, etc.) change remote data — confirm intent before running and surface what will change.

## Examples

```bash
./scripts/<service>.sh list-<things>
./scripts/<service>.sh <things>-in-<parent> 64abc123
./scripts/<service>.sh get-<thing> 64abc123
```

## Notes

- Every call prints `HTTP:<code>` to stderr (kept off stdout so the body pipes cleanly into the summariser). `2xx` = success; `401/403` = check credentials; `404` = bad id/path. On any `>=400` the command exits non-zero with the error body on stderr (nothing on stdout), so failures are catchable by exit code.
- Output (stdout) is summarised via `node`; non-JSON bodies (and a missing `node`) fall through raw. Add `--raw` (where supported) for the full payload.
- Coverage: <list operations covered; note anything intentionally omitted>.
