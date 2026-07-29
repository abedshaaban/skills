# Search Console API notes

Read this reference when interpreting URL Inspection output or planning a batch
audit.

## API surfaces

- Search Analytics:
  `POST https://www.googleapis.com/webmasters/v3/sites/{siteUrl}/searchAnalytics/query`
- Sites:
  `GET https://www.googleapis.com/webmasters/v3/sites`
- Sitemaps:
  `GET https://www.googleapis.com/webmasters/v3/sites/{siteUrl}/sitemaps`
- URL Inspection:
  `POST https://searchconsole.googleapis.com/v1/urlInspection/index:inspect`
- Read-only OAuth scope:
  `https://www.googleapis.com/auth/webmasters.readonly`

Encode `siteUrl` as one path segment. Preserve its exact Search Console form:
`sc-domain:example.com` or a URL-prefix property with its trailing slash.

## URL Inspection fields

The most relevant object is `inspectionResult.indexStatusResult`:

- `verdict`: high-level index verdict.
- `coverageState`: Google's human-readable coverage state.
- `robotsTxtState`: whether robots.txt blocked Google.
- `indexingState`: whether a page-level directive blocked indexing.
- `pageFetchState`: whether Google retrieved the page.
- `lastCrawlTime`: last successful crawl time when available.
- `googleCanonical`: canonical selected by Google.
- `userCanonical`: canonical declared by the site.
- `sitemap`: known containing sitemaps; not guaranteed exhaustive.
- `referringUrls`: known referring URLs; not guaranteed exhaustive.

The API reports the version in Google's index; it does not run the Search
Console live URL test. Pair it with `check-page` for current fetch/status,
canonical, meta robots, and X-Robots-Tag signals.

## Important limits

- URL Inspection: 2,000 queries/day and 600 queries/minute per property.
- Search Analytics response: 25,000 rows maximum per request.
- Search Analytics data exposure: up to 50,000 rows/day/search type.
- Search Analytics can omit anonymized or low-volume data. It is not a complete
  list of site URLs.

## Missing API surface

Google does not provide an API for the complete **Page indexing** report or its
bulk reason table. To find issues programmatically:

1. Obtain candidate URLs from a sitemap, crawl, CMS export, or URL file.
2. Inspect each candidate with URL Inspection within quota.
3. Check live HTTP/HTML signals separately.
4. Summarize blockers and warnings without claiming the sample is exhaustive.

## Sources

- https://developers.google.com/webmaster-tools/v1/api_reference_index
- https://developers.google.com/webmaster-tools/v1/searchanalytics/query
- https://developers.google.com/webmaster-tools/v1/urlInspection.index/inspect
- https://developers.google.com/webmaster-tools/v1/urlInspection.index/UrlInspectionResult
- https://developers.google.com/webmaster-tools/limits
- https://developers.google.com/identity/protocols/oauth2/service-account
