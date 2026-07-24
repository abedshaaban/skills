---
name: un-mcp
description: Convert an MCP server, a REST API, published API docs, a list of endpoints, or a user's own API wrapper/library into a lightweight agent skill backed by direct curl scripts, so nothing has to be loaded into context. Use when the user wants to "turn an MCP into a skill", "convert Trello/Linear/Notion/GitHub MCP", "wrap this API as a skill", "make a skill from these endpoints / this API doc / my wrapper", "stop the MCP bloating context", or points at any service, doc, or endpoint set and asks for a skill that queries it faster and cheaper than a live MCP. Also use when the user asks which MCPs or APIs could be converted.
---

# API → Skill Converter

Turn any API surface into a self-contained agent skill whose operations are plain `curl` calls. The generated skill loads only a small SKILL.md into context; each operation is a bash subcommand that hits the API directly. This is faster and far cheaper than keeping an MCP server connected — MCP tool schemas are re-injected into context every turn, while a bash script costs nothing until it runs.

The output is a new skill directory under `.agents/skills/<service>/` containing a `SKILL.md`, a single dispatcher script in `scripts/`, and a `SETUP.md` documenting credentials.

## Source types

The thing being converted does **not** have to be an MCP server. Handle whichever the user brings — the workflow is the same after discovery, only the discovery step differs:

- **MCP server** — live connected MCP, or a registry entry. Introspect its tool schemas.
- **REST API / published docs** — an API reference URL, OpenAPI/Swagger spec, or docs page. Fetch and extract the endpoint list.
- **Raw endpoint list** — the user pastes endpoints (`GET /boards`, `POST /cards …`). Use them directly; ask only for base URL and auth if missing.
- **User's own wrapper / library / internal service** — a script, SDK, or in-house backend the user wrote. Read the source (or the user's description) to learn the calls, base URL, and auth, then wrap the same HTTP calls in curl. This is common for internal tools like the LEC backend — no MCP or public docs exist, just the code.

If unsure which the user has, ask. If they have several (e.g. a live MCP *and* docs), use them together.

## When NOT to convert

Direct-REST conversion only works when the underlying service has a public HTTP API you can call with a static credential (API key / personal access token). Skip or warn the user if:

- The service has **no public REST API** (the MCP is the only interface). Say so plainly — a curl-backed skill is impossible; the MCP must stay.
- Auth is **interactive OAuth with no long-lived token** the user can paste. Ask the user to obtain a personal access token if the service offers one; otherwise stop.
- The MCP does local/stateful work (filesystem, in-memory graph) with no network API behind it.

## Workflow

### 1. Identify the target

If the user named a source (an MCP, an API, a docs URL, "my wrapper at …"), use it. If not, help them pick — offer the source types above and, for MCPs specifically:

- **Live connected MCPs**: MCP tools available this session appear as `mcp__<server>__<tool>` names and connected servers are listed in the system context. Enumerate the servers and offer them.
- **Registry search**: the `mcp-registry` tools (`mcp__mcp-registry__list_connectors`, `search_mcp_registry`, `suggest_connectors`) are deferred — load with ToolSearch (`select:mcp__mcp-registry__search_mcp_registry,mcp__mcp-registry__list_connectors`) and search by name.

Confirm the source with the user before building.

### 2. Discover the capabilities

Pull the operation list from whichever source(s) the user gave:

- **Live connected MCP** — the tool names and their JSON-Schema input definitions are the ground truth for operations and parameters. Read the schemas (via ToolSearch on the specific `mcp__<server>__*` tools) and list every tool: name, purpose, required/optional params.
- **Docs / URL / OpenAPI spec** — fetch with WebFetch (load via ToolSearch) and extract the endpoint list. For an OpenAPI/Swagger JSON, the `paths` object *is* the inventory (method, path, params, request body).
- **Raw endpoint list** — parse what the user pasted. Confirm base URL and auth if not stated.
- **User's own wrapper / internal service** — read the source with Read/Grep/Glob (or the repo submodule, e.g. `backend/`) to find the routes, base URL, and auth scheme. Ask the user for anything the code doesn't reveal (running host, how to get a token).

Produce an internal operation inventory: `operation name → what it does → params`.

### 3. Map each operation to a concrete HTTP call

For each operation, pin down: **method, path, query/body params, auth placement**. When the source is an MCP, the tool name/schema needs mapping to the underlying endpoint — see `references/rest-mapping.md` for the research method and worked mappings (Trello, GitHub, Linear, Notion, Slack, Asana, Atlassian/Jira). When the source is docs, an endpoint list, an OpenAPI spec, or the user's own wrapper, the HTTP call is often already explicit — just record it. If a service isn't listed and you only have an MCP, find its REST reference (WebFetch the official API docs) and derive the mapping.

Not every MCP tool needs its own subcommand. Collapse trivial variants, and prioritise the read + common-write operations the user actually asked about. Note anything you deliberately drop so the user knows the coverage.

### 4. Determine the auth model

Identify how the REST API authenticates and which env vars the script will read. Common shapes:

- **Query-param key+token** (Trello): `?key=$KEY&token=$TOKEN`
- **Bearer token header** (Linear, Notion, Slack, GitHub, Atlassian): `-H "Authorization: Bearer $TOKEN"` (GitHub also accepts `token`, Atlassian uses Basic with email+API-token)
- **Custom header** (some services): `-H "X-Api-Key: $KEY"`

Never hardcode credentials. Read them from environment variables and document them in `SETUP.md`. Tell the user exactly where to generate each credential.

**Keep secrets off the command line.** A token passed as a curl argv flag (`-H "Authorization: …"`, `-u user:token`, or in the URL) is visible in `ps` output and shell history to any local process. Pass the URL and the auth line to curl through a stdin config instead (`-K -` with a heredoc), so only non-secret flags stay on argv. See the `call` function in `assets/dispatcher-template.sh` and the generated trello skill for the exact pattern.

### 5. Generate the skill

Create `.agents/skills/<service>/` (kebab-case service name). Use the templates in `assets/` as the starting point — do not write from scratch:

- `assets/skill-template.md` → the generated `SKILL.md`. Fill in the service name, description (make triggering pushy — see the converter's own description as a model), the env-var list, and one documented subcommand per operation with a one-line "when to use".
- `assets/dispatcher-template.sh` → `scripts/<service>.sh`. It is a `case`-dispatch bash script: `./scripts/<service>.sh <command> [args...]`. Add one `case` arm per operation, each a single curl. Set the real `BASE`, pick the auth line in `call`, and keep the `help` arm.
- `assets/setup-template.md` → `SETUP.md`. Document every required variable, where to obtain it (with scope notes), and the gitignored-`.env` workflow.

`chmod +x` the dispatcher script.

Design rules for the generated skill:

- **One dispatcher, many subcommands** — keeps the loaded SKILL.md small; the agent reads a command table, not N script files.
- **Read-heavy first** — cover list/get operations fully; they are the common case and safe to verify.
- **Guard writes** — destructive/write subcommands (delete, archive, send) print what they will do and require an explicit flag or confirmed argument, mirroring the safety rules; never make them the default path.
- **Every curl reports status**: use `-sS` and `-w $'\n%{http_code}'`, then split the trailing line off and print it to **stderr** (`HTTP:<code>`), leaving only the body on stdout. Status inline on stdout corrupts the JSON the summariser parses, so summarised reads return nothing. Use `-g` for bracketed query params.
- **Fail on HTTP errors**: when the code is `>=400`, send the error body + status to stderr, print nothing to stdout, and `return 1`. This makes failures catchable by exit code and stops `pretty` from reshaping an error object (`{"message":"..."}`) into a misleading null-filled result. Under `set -euo pipefail` a failing `call | pretty` then aborts the one-shot command cleanly.
- **Summarise, don't dump** — pass the body to `node` with a JS arrow-fn filter (`pretty 'j=>j.map(x=>({id:x.id,name:x.name}))'`) when a raw payload would be huge. Buffer stdin and, on a parse error or missing `node`, print the raw body instead of vanishing; keep raw available via a `--raw` style arm when useful. Use `node` — not `jq` — as the summariser: it is cross-platform (Windows/macOS/Linux), needs no OS-specific install, and is the usual agent runtime, whereas `jq` is installed nowhere by default.
- **Declare `node` as a soft dependency and fail loud if absent** — `node` is what makes the skill cheaper than the MCP (it trims payloads before they reach context). List it in `SETUP.md`, and have the dispatcher print a one-line stderr warning when `node` is missing, so the fallback to raw payloads is visible, not a silent context-bloat regression. The skill must still work without it (raw output), so never make `node` a hard requirement for reads.
- **Never hand-concatenate JSON bodies** — build them with `node -e 'process.stdout.write(JSON.stringify({...}))'` passing values as `process.argv`, so quotes/backslashes in user input can't break out or inject fields. For form-encoded APIs, URL-encode each value with the pure-bash percent-encoder (see the generated trello skill's `enc`) — that needs no external tool at all.
- **Fail loud on missing creds** — the dispatcher checks required env vars up front and exits with a clear message naming the missing var and where to get it.

### 6. Verify before handing off

Prove the generated skill works, don't just assert it:

- Ask the user to populate the credentials (point at `SETUP.md`). Do **not** ask them to paste raw secrets into chat — have them fill the gitignored `.env` the script sources.
- Run one **read-only** subcommand (e.g. `list-boards`, `list-issues`) and confirm a `HTTP:200` with real data.
- If auth fails, report the exact error class/status (redacted — never echo the token) and fix the mapping or auth placement at the source.

Report: which operations the skill covers, which were dropped and why, the verified read command, and the credentials the user still needs to set.

## Output structure

```
.agents/skills/<service>/
├── SKILL.md            # command table + when-to-use per operation
├── SETUP.md            # required credentials + where to get them
└── scripts/
    └── <service>.sh    # case-dispatch, one curl per command
```

## Reference files

- `references/rest-mapping.md` — how to derive REST endpoints from MCP tools, auth patterns, and worked mappings for Trello, GitHub, Linear, Notion, Slack, Asana, Atlassian/Jira.
- `assets/skill-template.md` — starting point for the generated SKILL.md.
- `assets/setup-template.md` — starting point for the generated SETUP.md.
- `assets/dispatcher-template.sh` — starting point for the generated dispatcher script.
