---
name: google-search-console
description: Query Google Search Console directly through its REST APIs and diagnose why URLs are not indexed. Use whenever the user asks about GSC/Search Console properties, search performance, clicks, impressions, CTR, rankings, queries, pages, sitemaps, URL inspection, indexing coverage, robots/noindex/fetch/canonical problems, or wants to audit a URL list or sitemap for indexing issues. Also use to check a live page's HTTP status, canonical, robots meta, and X-Robots-Tag without opening Search Console.
---

# Google Search Console

Use the dispatcher at `scripts/google-search-console.sh`. It calls the official
Search Console REST APIs directly and summarizes responses before they enter
context.

## Setup

Read [SETUP.md](SETUP.md) if authentication is not already configured. The
preferred setup uses the same `GOOGLE_APPLICATION_CREDENTIALS` service-account
JSON as Google's client libraries. The service account must be a user of the
Search Console property.

## Workflow

1. Run `list-sites` first when the exact property identifier is unknown.
2. Use the identifier exactly as returned:
   - Domain property: `sc-domain:example.com`
   - URL-prefix property: `https://www.example.com/` (preserve trailing slash)
3. Use analytics commands for performance data.
4. Use `inspect-url`, `inspect-urls`, or `inspect-sitemap` for Google's indexed
   version and indexing verdict.
5. Use `check-page` for the current live HTTP/HTML signals. A passing live check
   does not prove that Google indexed the page.

## Commands

Run: `./scripts/google-search-console.sh <command> [args...]`

| Command | Args | Use |
|---|---|---|
| `list-sites` | — | List accessible Search Console properties and permission levels |
| `site-info` | `<siteUrl>` | Get one property |
| `analytics` | `<siteUrl> <start> <end> [dimensions] [limit] [startRow] [type]` | Query performance; dimensions are comma-separated |
| `analytics-json` | `<siteUrl> '<request-json>'` | Use the full Search Analytics request body for filters/advanced queries |
| `top-queries` | `<siteUrl> <start> <end> [limit]` | Top queries by clicks |
| `top-pages` | `<siteUrl> <start> <end> [limit]` | Top pages by clicks |
| `page-queries` | `<siteUrl> <pageUrl> <start> <end> [limit]` | Queries for one exact page |
| `list-sitemaps` | `<siteUrl>` | Submitted sitemaps and Google processing counts |
| `sitemap-info` | `<siteUrl> <sitemapUrl>` | Detail for one submitted sitemap |
| `sitemap-urls` | `<sitemapUrl> [limit]` | Read URLs (or child sitemaps) from public XML without GSC auth |
| `inspect-url` | `<siteUrl> <url> [language]` | Google's index verdict and diagnosed blockers/warnings |
| `inspect-urls` | `<siteUrl> <file> [max] [language]` | Inspect newline-delimited URLs and summarize failures |
| `inspect-sitemap` | `<siteUrl> <sitemapUrl> [max] [language]` | Inspect URLs from a sitemap; follows one sitemap-index level |
| `check-page` | `<url>` | Check current status, final URL, canonical, meta robots, and X-Robots-Tag |
| `help` | — | Print command names |

Dates use `YYYY-MM-DD`. Search Analytics permits 1–25,000 rows per response;
use `startRow` for the next page. `type` defaults to `web`.

## Examples

```bash
./scripts/google-search-console.sh list-sites
./scripts/google-search-console.sh top-pages 'sc-domain:example.com' 2026-06-01 2026-06-30 100
./scripts/google-search-console.sh page-queries 'sc-domain:example.com' 'https://example.com/page' 2026-06-01 2026-06-30
./scripts/google-search-console.sh inspect-url 'sc-domain:example.com' 'https://example.com/page'
./scripts/google-search-console.sh inspect-sitemap 'sc-domain:example.com' 'https://example.com/sitemap.xml' 100
./scripts/google-search-console.sh check-page 'https://example.com/page'
```

## Interpretation rules

- Treat `inspectionResult.indexStatusResult.verdict` as Google's high-level
  index verdict. Report the accompanying `coverageState` verbatim.
- Treat blocked robots, a disallowing indexing state, and unsuccessful page
  fetch as likely indexing blockers.
- Treat canonical mismatch as a warning: Google may index the selected
  canonical instead of the inspected URL.
- Distinguish "no Search Analytics row" from "not indexed"; the Performance API
  is traffic data and is not an index inventory.
- The API exposes URL inspection one URL at a time. It does **not** expose the
  Search Console Page Indexing report or its complete bulk issue table.
- `inspect-sitemap` samples up to `max` URLs (default 100). Do not imply that a
  sample is a complete site audit.
- URL Inspection quotas are property-scoped. Keep batches bounded and do not
  retry quota failures in a tight loop. See [references/api-notes.md](references/api-notes.md)
  when planning large audits or interpreting response fields.

All commands are read-only. Every API call prints `HTTP:<code>` to stderr and
keeps JSON on stdout. HTTP errors exit non-zero.
