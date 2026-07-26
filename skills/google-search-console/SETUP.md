# Google Search Console skill — credentials setup

The dispatcher auto-sources the project-root `.env`, then a skill-local `.env`
(local values override project values). Never commit either filled-in file.

## Prerequisites

- `curl`
- Node.js 20 or newer
- A Google Cloud project with the **Google Search Console API** enabled
- A service account that has access to the Search Console properties

## Preferred setup: service account

This matches the authentication used by
`gsc-obsidian-seo-pipeline`.

1. Create or reuse a Google Cloud service account and JSON key.
2. In Search Console, open **Settings → Users and permissions → Add user**.
3. Add the service account's `client_email` from the JSON key. Read access is
   sufficient for this read-only skill.
4. Put the absolute key path in a gitignored `.env`:

```bash
GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/google-service-account.json
```

The script reads the key locally, signs a short-lived JWT with Node's built-in
crypto module, exchanges it for an OAuth access token, and sends that token to
Google through curl's stdin config. The private key and access token are never
printed or placed in curl's command-line arguments.

## Optional: temporary access token

For a short-lived manual session, set:

```bash
GOOGLE_SEARCH_CONSOLE_ACCESS_TOKEN=
```

This overrides service-account authentication. The token needs
`https://www.googleapis.com/auth/webmasters.readonly`.

## Optional default property

```bash
GOOGLE_SEARCH_CONSOLE_SITE_URL=sc-domain:example.com
```

This is documentation/convenience metadata; commands still take `siteUrl`
explicitly so the property is never ambiguous.

## Verify

```bash
./scripts/google-search-console.sh list-sites
```

Expected: `HTTP:200` on stderr and a JSON list of properties on stdout. A `403`
usually means the API is disabled or the service-account email was not added to
the property. A successful empty list means the authenticated identity has no
Search Console properties.

## Security

- Treat the service-account JSON as a password.
- Keep credential files outside the skill and repository.
- Confirm `.env` is ignored with `git check-ignore .env`.
- If a JSON key is exposed, disable/delete that key in Google Cloud IAM and
  create a replacement.
