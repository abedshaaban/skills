# REST Mapping Reference

How to turn an MCP tool into a direct HTTP call, plus worked mappings for common services.

## The research method (any service)

An MCP server is almost always a thin wrapper over a public REST API. To find the real call behind a tool:

1. **Name maps to resource + verb.** `mcp__trello__get_cards_in_list` → GET the cards collection scoped to a list. `create_issue` → POST to the issues collection. Read the tool's input schema: required params are usually path/query params, the body object maps to the request body.
2. **Find the official API reference.** WebFetch the service's REST docs (search "<service> REST API reference"). Confirm base URL, the exact path, and the auth header.
3. **Confirm auth.** Look for "Authentication" in the docs — key+token in query, Bearer header, or Basic. Note the token type the user can generate without an interactive flow.
4. **Note pagination & rate limits.** Most list endpoints paginate (`?limit=`, `?page=`, cursor). Cover the common case; document the limit.

When a service is not listed below, this method is enough — derive the mapping from the official docs.

## Auth patterns

| Pattern | Example services | curl form |
|---|---|---|
| Key + token in query | Trello | `"...?key=$KEY&token=$TOKEN"` |
| Bearer header | Linear, Notion, Slack, GitHub | `-H "Authorization: Bearer $TOKEN"` |
| Basic (email:token) | Atlassian / Jira | `-u "$EMAIL:$API_TOKEN"` |
| Custom header | misc | `-H "X-Api-Key: $KEY"` |

Notion also requires a version header: `-H "Notion-Version: 2022-06-28"`.

## Worked mappings

### Trello — base `https://api.trello.com/1`
Auth: `?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN` on every request. Key+token from https://trello.com/power-ups/admin (or https://trello.com/app-key).

| Operation | Method + path |
|---|---|
| List boards | `GET /members/me/boards` |
| Lists in a board | `GET /boards/{boardId}/lists` |
| Cards in a list | `GET /lists/{listId}/cards` |
| Card detail | `GET /cards/{cardId}` |
| Create card | `POST /cards` body `idList`, `name`, `desc` |
| Move card | `PUT /cards/{cardId}` body `idList` |
| Add comment | `POST /cards/{cardId}/actions/comments` body `text` |

### GitHub — base `https://api.github.com`
Auth: `-H "Authorization: Bearer $GITHUB_TOKEN"` + `-H "Accept: application/vnd.github+json"`. Fine-grained/classic PAT from https://github.com/settings/tokens.

| Operation | Method + path |
|---|---|
| List repos | `GET /user/repos` |
| List issues | `GET /repos/{owner}/{repo}/issues` |
| Issue detail | `GET /repos/{owner}/{repo}/issues/{number}` |
| Create issue | `POST /repos/{owner}/{repo}/issues` body `title`, `body` |
| List PRs | `GET /repos/{owner}/{repo}/pulls` |
| Comment on issue | `POST /repos/{owner}/{repo}/issues/{number}/comments` body `body` |

### Linear — base `https://api.linear.app/graphql` (GraphQL, not REST)
Auth: `-H "Authorization: $LINEAR_API_KEY"` (personal API key, no "Bearer" prefix). Key from Linear → Settings → Security & access → API. All operations are POSTs with a `query`/`mutation` in the JSON body. Example list issues:
```bash
curl -sS -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" -H "Content-Type: application/json" \
  -d '{"query":"{ issues(first: 20) { nodes { id identifier title state { name } } } }"}'
```

### Notion — base `https://api.notion.com/v1`
Auth: `-H "Authorization: Bearer $NOTION_TOKEN"` + `-H "Notion-Version: 2022-06-28"`. Internal integration token from https://www.notion.so/my-integrations (share the target pages/DBs with the integration).

| Operation | Method + path |
|---|---|
| Query a database | `POST /databases/{databaseId}/query` |
| Page detail | `GET /pages/{pageId}` |
| Create page | `POST /pages` body `parent` + `properties` |
| Search | `POST /search` body `query` |

### Slack — base `https://slack.com/api`
Auth: `-H "Authorization: Bearer $SLACK_TOKEN"`. Bot/user token (`xoxb-`/`xoxp-`) from a Slack app's OAuth & Permissions page. Note: `chat.postMessage` is a write — guard it.

| Operation | Method + path |
|---|---|
| List channels | `GET /conversations.list` |
| Channel history | `GET /conversations.history?channel={id}` |
| Post message | `POST /chat.postMessage` body `channel`, `text` (guard) |

### Asana — base `https://app.asana.com/api/1.0`
Auth: `-H "Authorization: Bearer $ASANA_TOKEN"`. Personal access token from Asana → My Settings → Apps → Developer apps.

| Operation | Method + path |
|---|---|
| List workspaces | `GET /workspaces` |
| Tasks in project | `GET /projects/{projectId}/tasks` |
| Task detail | `GET /tasks/{taskId}` |
| Create task | `POST /tasks` body `data.name`, `data.projects` |

### Atlassian / Jira — base `https://{site}.atlassian.net/rest/api/3`
Auth: `-u "$JIRA_EMAIL:$JIRA_API_TOKEN"` (Basic). API token from https://id.atlassian.com/manage-profile/security/api-tokens.

| Operation | Method + path |
|---|---|
| Search issues (JQL) | `GET /search/jql?jql={jql}` (the older `GET /search` is deprecated — confirm the current path in the docs) |
| Issue detail | `GET /issue/{key}` |
| Create issue | `POST /issue` body `fields` |
| Add comment | `POST /issue/{key}/comment` body `body` |

## Verifying a mapping

Always test with a read-only endpoint first (`list-*` / `get-*`). A `HTTP:200` with a recognisable payload confirms both the endpoint and the auth. A `401/403` means auth placement is wrong (wrong header, missing prefix, wrong token type). A `404` usually means the path or an ID is wrong.
