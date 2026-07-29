#!/usr/bin/env bash
# Direct, read-only Google Search Console REST dispatcher.
set -euo pipefail

WEBMASTERS_BASE="https://www.googleapis.com/webmasters/v3"
INSPECTION_URL="https://searchconsole.googleapis.com/v1/urlInspection/index:inspect"
TOKEN_URL="https://oauth2.googleapis.com/token"
READONLY_SCOPE="https://www.googleapis.com/auth/webmasters.readonly"

_dir="$(cd "$(dirname "$0")" && pwd)"
_root="$(git -C "$_dir" rev-parse --show-toplevel 2>/dev/null || echo "$_dir/../../../..")"
for _envf in "$_root/.env" "$_dir/../.env"; do
  if [[ -f "$_envf" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$_envf"
    set +a
  fi
done

require_node() {
  command -v node >/dev/null 2>&1 || {
    echo "Missing dependency: node (Node.js 20+; see SETUP.md)" >&2
    exit 1
  }
}

enc() {
  local LC_ALL=C s="$1" i c n out=""
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) printf -v n '%d' "'$c"; printf -v c '%%%02X' "$((n & 0xff))"; out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

http_result() {
  local resp="$1" code body
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  if [[ ! "$code" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$resp" >&2
    return 1
  fi
  if ((code >= 400)); then
    printf '%s\n' "$body" >&2
    printf 'HTTP:%s\n' "$code" >&2
    return 1
  fi
  printf '%s\n' "$body"
  printf 'HTTP:%s\n' "$code" >&2
}

get_access_token() {
  if [[ -n "${GOOGLE_SEARCH_CONSOLE_ACCESS_TOKEN:-}" ]]; then
    printf '%s' "$GOOGLE_SEARCH_CONSOLE_ACCESS_TOKEN"
    return
  fi

  local credentials="${GOOGLE_APPLICATION_CREDENTIALS:-}"
  if [[ -z "$credentials" ]]; then
    echo "Missing GOOGLE_APPLICATION_CREDENTIALS or GOOGLE_SEARCH_CONSOLE_ACCESS_TOKEN (see SETUP.md)" >&2
    exit 1
  fi
  if [[ ! -f "$credentials" ]]; then
    echo "Credential file does not exist: $credentials" >&2
    exit 1
  fi
  require_node

  local assertion token_resp token_code token_body
  assertion="$(node -e '
const fs = require("fs");
const crypto = require("crypto");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!c.client_email || !c.private_key) throw new Error("service-account JSON needs client_email and private_key");
const now = Math.floor(Date.now() / 1000);
const b64 = value => Buffer.from(JSON.stringify(value)).toString("base64url");
const input = b64({alg:"RS256",typ:"JWT"}) + "." + b64({
  iss:c.client_email,
  scope:process.argv[2],
  aud:process.argv[3],
  iat:now,
  exp:now + 3600
});
const signature = crypto.sign("RSA-SHA256", Buffer.from(input), c.private_key).toString("base64url");
process.stdout.write(input + "." + signature);
' "$credentials" "$READONLY_SCOPE" "$TOKEN_URL")"

  token_resp="$(curl -sS -X POST -w $'\n%{http_code}' -K - <<CFG
url = "$TOKEN_URL"
header = "Content-Type: application/x-www-form-urlencoded"
data = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=$assertion"
CFG
)"
  token_code="${token_resp##*$'\n'}"
  token_body="${token_resp%$'\n'*}"
  if [[ ! "$token_code" =~ ^2[0-9][0-9]$ ]]; then
    printf '%s\n' "$token_body" >&2
    printf 'OAuth HTTP:%s\n' "$token_code" >&2
    exit 1
  fi
  printf '%s' "$token_body" | node -e '
let s=""; process.stdin.setEncoding("utf8");
process.stdin.on("data",d=>s+=d).on("end",()=>{
  const j=JSON.parse(s);
  if (!j.access_token) throw new Error("OAuth response did not include access_token");
  process.stdout.write(j.access_token);
});'
}

ACCESS_TOKEN=""

ensure_auth() {
  if [[ -z "$ACCESS_TOKEN" ]]; then
    ACCESS_TOKEN="$(get_access_token)"
  fi
}

api_call() {
  local method="$1" url="$2"
  shift 2
  ensure_auth
  local resp
  resp="$(curl -g -sS -X "$method" -w $'\n%{http_code}' "$@" -K - <<CFG
url = "$url"
header = "Authorization: Bearer $ACCESS_TOKEN"
CFG
)"
  http_result "$resp"
}

pretty() {
  local body
  body="$(cat)"
  [[ -z "$body" ]] && return
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$body" | node -e '
let s="";
process.stdin.setEncoding("utf8");
process.stdin.on("data",d=>s+=d).on("end",()=>{
  try {
    const j=JSON.parse(s);
    const out=(0,eval)(process.argv[1])(j);
    console.log(typeof out === "string" ? out : JSON.stringify(out,null,2));
  } catch (_) {
    process.stdout.write(s.endsWith("\n") ? s : s+"\n");
  }
});' "$1"
  else
    printf '%s\n' "$body"
  fi
}

validate_date() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
    echo "Invalid date '$1'; expected YYYY-MM-DD" >&2
    exit 1
  }
}

validate_limit() {
  local value="$1" max="$2" label="$3"
  [[ "$value" =~ ^[0-9]+$ ]] && ((value >= 1 && value <= max)) || {
    echo "$label must be an integer from 1 to $max" >&2
    exit 1
  }
}

analytics_body() {
  node -e '
const dimensions=process.argv[3].split(",").map(x=>x.trim()).filter(Boolean);
const body={
  startDate:process.argv[1],
  endDate:process.argv[2],
  dimensions,
  rowLimit:Number(process.argv[4]),
  startRow:Number(process.argv[5]),
  type:process.argv[6]
};
process.stdout.write(JSON.stringify(body));
' "$1" "$2" "$3" "$4" "$5" "$6"
}

inspection_summary_filter='j=>{const r=(j.inspectionResult||{}),s=(r.indexStatusResult||{}),blockers=[],warnings=[];if(s.robotsTxtState==="BLOCKED")blockers.push("Blocked by robots.txt");if(s.indexingState&&s.indexingState!=="INDEXING_ALLOWED"&&s.indexingState!=="INDEXING_STATE_UNSPECIFIED")blockers.push("Indexing state: "+s.indexingState);if(s.pageFetchState&&s.pageFetchState!=="SUCCESSFUL"&&s.pageFetchState!=="PAGE_FETCH_STATE_UNSPECIFIED")blockers.push("Page fetch: "+s.pageFetchState);if(s.verdict&&s.verdict!=="PASS"&&s.coverageState)blockers.push("Coverage: "+s.coverageState);if(s.googleCanonical&&s.userCanonical&&s.googleCanonical!==s.userCanonical)warnings.push("Google selected a different canonical");return {indexed:s.verdict==="PASS",verdict:s.verdict||null,coverageState:s.coverageState||null,robotsTxtState:s.robotsTxtState||null,indexingState:s.indexingState||null,pageFetchState:s.pageFetchState||null,lastCrawlTime:s.lastCrawlTime||null,googleCanonical:s.googleCanonical||null,userCanonical:s.userCanonical||null,crawledAs:s.crawledAs||null,sitemaps:s.sitemap||[],referringUrls:s.referringUrls||[],blockers,warnings,mobileUsability:r.mobileUsabilityResult&&r.mobileUsabilityResult.verdict,richResults:r.richResultsResult&&r.richResultsResult.verdict}}'

inspect_raw() {
  local site="$1" url="$2" language="$3" body
  body="$(node -e 'process.stdout.write(JSON.stringify({inspectionUrl:process.argv[1],siteUrl:process.argv[2],languageCode:process.argv[3]}))' "$url" "$site" "$language")"
  api_call POST "$INSPECTION_URL" -H "Content-Type: application/json" --data-binary "$body"
}

inspect_file() {
  local site="$1" file="$2" max="$3" language="$4"
  [[ -r "$file" ]] || { echo "URL input is not readable: $file" >&2; exit 1; }
  validate_limit "$max" 2000 "max"
  require_node

  local tmp count=0 url raw summary
  tmp="$(mktemp "${TMPDIR:-/tmp}/gsc-inspect.XXXXXX")"
  while IFS= read -r url || [[ -n "$url" ]]; do
    url="${url%$'\r'}"
    [[ -z "$url" || "$url" == \#* ]] && continue
    case "$url" in
      http://*|https://*) ;;
      *) echo "Skipping non-HTTP URL: $url" >&2; continue ;;
    esac
    ((count += 1))
    if raw="$(inspect_raw "$site" "$url" "$language")"; then
      summary="$(printf '%s' "$raw" | pretty "$inspection_summary_filter")"
      node -e 'const j=JSON.parse(process.argv[2]);j.url=process.argv[1];process.stdout.write(JSON.stringify(j)+"\n")' "$url" "$summary" >> "$tmp"
    else
      node -e 'process.stdout.write(JSON.stringify({url:process.argv[1],error:"inspection request failed"})+"\n")' "$url" >> "$tmp"
    fi
    ((count >= max)) && break
    sleep 0.12
  done < "$file"

  node -e '
const fs=require("fs");
const rows=fs.readFileSync(process.argv[1],"utf8").split(/\n/).filter(Boolean).map(JSON.parse);
const issueRows=rows.filter(r=>r.error || !r.indexed || (r.blockers||[]).length || (r.warnings||[]).length);
const coverage={};
for(const r of rows){const k=r.coverageState||r.error||"unknown";coverage[k]=(coverage[k]||0)+1;}
console.log(JSON.stringify({
  summary:{inspected:rows.length,indexed:rows.filter(r=>r.indexed).length,withIssues:issueRows.length,coverage},
  issues:issueRows,
  results:rows
},null,2));
' "$tmp"
  rm -f "$tmp"
}

extract_sitemap() {
  local sitemap_url="$1" output_file="$2" limit="$3" xml_file
  xml_file="$(mktemp "${TMPDIR:-/tmp}/gsc-sitemap.XXXXXX")"
  curl -sS --fail --location --max-time 45 "$sitemap_url" > "$xml_file"
  node -e '
const fs=require("fs");
const xml=fs.readFileSync(process.argv[1],"utf8");
const decode=s=>s.replace(/&amp;/g,"&").replace(/&lt;/g,"<").replace(/&gt;/g,">").replace(/&quot;/g,"\"").replace(/&#39;|&apos;/g,"'\''");
const values=[...xml.matchAll(/<loc\b[^>]*>([\s\S]*?)<\/loc>/gi)].map(m=>decode(m[1].trim()));
const type=/<sitemapindex\b/i.test(xml)?"index":"urlset";
process.stdout.write(type+"\n"+values.slice(0,Number(process.argv[3])).join("\n")+(values.length?"\n":""));
' "$xml_file" "$sitemap_url" "$limit" > "$output_file"
  rm -f "$xml_file"
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  list-sites)
    api_call GET "$WEBMASTERS_BASE/sites" \
      | pretty 'j=>(j.siteEntry||[]).map(x=>({siteUrl:x.siteUrl,permissionLevel:x.permissionLevel}))'
    ;;

  site-info)
    site="${1:?usage: site-info <siteUrl>}"
    api_call GET "$WEBMASTERS_BASE/sites/$(enc "$site")" | pretty 'j=>j'
    ;;

  analytics)
    require_node
    site="${1:?usage: analytics <siteUrl> <start> <end> [dimensions] [limit] [startRow] [type]}"
    start="${2:?usage: analytics <siteUrl> <start> <end> [dimensions] [limit] [startRow] [type]}"
    end="${3:?usage: analytics <siteUrl> <start> <end> [dimensions] [limit] [startRow] [type]}"
    dimensions="${4:-query}"
    limit="${5:-1000}"
    start_row="${6:-0}"
    search_type="${7:-web}"
    validate_date "$start"; validate_date "$end"; validate_limit "$limit" 25000 "limit"
    [[ "$start_row" =~ ^[0-9]+$ ]] || { echo "startRow must be a non-negative integer" >&2; exit 1; }
    body="$(analytics_body "$start" "$end" "$dimensions" "$limit" "$start_row" "$search_type")"
    api_call POST "$WEBMASTERS_BASE/sites/$(enc "$site")/searchAnalytics/query" \
      -H "Content-Type: application/json" --data-binary "$body" | pretty 'j=>j'
    ;;

  analytics-json)
    require_node
    site="${1:?usage: analytics-json <siteUrl> '<request-json>'}"
    body="${2:?usage: analytics-json <siteUrl> '<request-json>'}"
    node -e 'JSON.parse(process.argv[1])' "$body"
    api_call POST "$WEBMASTERS_BASE/sites/$(enc "$site")/searchAnalytics/query" \
      -H "Content-Type: application/json" --data-binary "$body" | pretty 'j=>j'
    ;;

  top-queries|top-pages)
    require_node
    site="${1:?usage: $cmd <siteUrl> <start> <end> [limit]}"
    start="${2:?usage: $cmd <siteUrl> <start> <end> [limit]}"
    end="${3:?usage: $cmd <siteUrl> <start> <end> [limit]}"
    limit="${4:-100}"
    validate_date "$start"; validate_date "$end"; validate_limit "$limit" 25000 "limit"
    [[ "$cmd" == "top-queries" ]] && dimension="query" || dimension="page"
    body="$(analytics_body "$start" "$end" "$dimension" "$limit" 0 web)"
    api_call POST "$WEBMASTERS_BASE/sites/$(enc "$site")/searchAnalytics/query" \
      -H "Content-Type: application/json" --data-binary "$body" \
      | pretty 'j=>({rows:(j.rows||[]).map(r=>({value:(r.keys||[])[0],clicks:r.clicks||0,impressions:r.impressions||0,ctr:r.ctr||0,position:r.position||0})),responseAggregationType:j.responseAggregationType,metadata:j.metadata})'
    ;;

  page-queries)
    require_node
    site="${1:?usage: page-queries <siteUrl> <pageUrl> <start> <end> [limit]}"
    page="${2:?usage: page-queries <siteUrl> <pageUrl> <start> <end> [limit]}"
    start="${3:?usage: page-queries <siteUrl> <pageUrl> <start> <end> [limit]}"
    end="${4:?usage: page-queries <siteUrl> <pageUrl> <start> <end> [limit]}"
    limit="${5:-100}"
    validate_date "$start"; validate_date "$end"; validate_limit "$limit" 25000 "limit"
    body="$(node -e 'process.stdout.write(JSON.stringify({startDate:process.argv[1],endDate:process.argv[2],dimensions:["query"],dimensionFilterGroups:[{groupType:"and",filters:[{dimension:"page",operator:"equals",expression:process.argv[3]}]}],rowLimit:Number(process.argv[4]),type:"web"}))' "$start" "$end" "$page" "$limit")"
    api_call POST "$WEBMASTERS_BASE/sites/$(enc "$site")/searchAnalytics/query" \
      -H "Content-Type: application/json" --data-binary "$body" \
      | pretty 'j=>({rows:(j.rows||[]).map(r=>({query:(r.keys||[])[0],clicks:r.clicks||0,impressions:r.impressions||0,ctr:r.ctr||0,position:r.position||0}))})'
    ;;

  list-sitemaps)
    site="${1:?usage: list-sitemaps <siteUrl>}"
    api_call GET "$WEBMASTERS_BASE/sites/$(enc "$site")/sitemaps" \
      | pretty 'j=>(j.sitemap||[]).map(s=>({path:s.path,type:s.type,isPending:s.isPending,isSitemapsIndex:s.isSitemapsIndex,lastSubmitted:s.lastSubmitted,lastDownloaded:s.lastDownloaded,warnings:s.warnings,errors:s.errors,contents:s.contents}))'
    ;;

  sitemap-info)
    site="${1:?usage: sitemap-info <siteUrl> <sitemapUrl>}"
    sitemap="${2:?usage: sitemap-info <siteUrl> <sitemapUrl>}"
    api_call GET "$WEBMASTERS_BASE/sites/$(enc "$site")/sitemaps/$(enc "$sitemap")" | pretty 'j=>j'
    ;;

  sitemap-urls)
    require_node
    sitemap="${1:?usage: sitemap-urls <sitemapUrl> [limit]}"
    limit="${2:-1000}"
    validate_limit "$limit" 50000 "limit"
    tmp="$(mktemp "${TMPDIR:-/tmp}/gsc-sitemap-list.XXXXXX")"
    extract_sitemap "$sitemap" "$tmp" "$limit"
    node -e 'const fs=require("fs"),a=fs.readFileSync(process.argv[1],"utf8").trim().split(/\n/);const type=a.shift()||"unknown";console.log(JSON.stringify({type,entries:a.filter(Boolean)},null,2))' "$tmp"
    rm -f "$tmp"
    ;;

  inspect-url)
    require_node
    site="${1:?usage: inspect-url <siteUrl> <url> [language]}"
    url="${2:?usage: inspect-url <siteUrl> <url> [language]}"
    language="${3:-en-US}"
    inspect_raw "$site" "$url" "$language" | pretty "$inspection_summary_filter"
    ;;

  inspect-urls)
    site="${1:?usage: inspect-urls <siteUrl> <file> [max] [language]}"
    file="${2:?usage: inspect-urls <siteUrl> <file> [max] [language]}"
    max="${3:-100}"
    language="${4:-en-US}"
    inspect_file "$site" "$file" "$max" "$language"
    ;;

  inspect-sitemap)
    require_node
    site="${1:?usage: inspect-sitemap <siteUrl> <sitemapUrl> [max] [language]}"
    sitemap="${2:?usage: inspect-sitemap <siteUrl> <sitemapUrl> [max] [language]}"
    max="${3:-100}"
    language="${4:-en-US}"
    validate_limit "$max" 2000 "max"
    first="$(mktemp "${TMPDIR:-/tmp}/gsc-sitemap-first.XXXXXX")"
    urls="$(mktemp "${TMPDIR:-/tmp}/gsc-sitemap-urls.XXXXXX")"
    extract_sitemap "$sitemap" "$first" 50000
    read -r sitemap_type < "$first"
    if [[ "$sitemap_type" == "index" ]]; then
      tail -n +2 "$first" | while IFS= read -r child; do
        [[ -z "$child" ]] && continue
        child_file="$(mktemp "${TMPDIR:-/tmp}/gsc-sitemap-child.XXXXXX")"
        if extract_sitemap "$child" "$child_file" "$max"; then
          tail -n +2 "$child_file" >> "$urls"
        else
          echo "Could not read child sitemap: $child" >&2
        fi
        rm -f "$child_file"
        [[ "$(wc -l < "$urls" | tr -d ' ')" -ge "$max" ]] && break
      done
    else
      tail -n +2 "$first" > "$urls"
    fi
    awk -v max="$max" '!seen[$0]++ { print; count += 1; if (count >= max) exit }' "$urls" > "$urls.unique"
    inspect_file "$site" "$urls.unique" "$max" "$language"
    rm -f "$first" "$urls" "$urls.unique"
    ;;

  check-page)
    require_node
    url="${1:?usage: check-page <url>}"
    headers="$(mktemp "${TMPDIR:-/tmp}/gsc-page-headers.XXXXXX")"
    body_file="$(mktemp "${TMPDIR:-/tmp}/gsc-page-body.XXXXXX")"
    meta="$(curl -sS --location --max-time 45 --dump-header "$headers" --output "$body_file" \
      --write-out $'%{http_code}\n%{url_effective}\n%{content_type}\n%{num_redirects}' "$url")"
    node -e '
const fs=require("fs");
const lines=process.argv[1].split("\n");
const meta={status:Number(lines[0]),finalUrl:lines[1],contentType:lines[2]||null,redirects:Number(lines[3])};
const headers=fs.readFileSync(process.argv[2],"utf8");
const html=fs.readFileSync(process.argv[3],"utf8");
const finalBlock=headers.trim().split(/\r?\n\r?\n/).filter(Boolean).pop()||"";
const xrobots=(finalBlock.match(/^x-robots-tag:\s*(.+)$/im)||[])[1]||null;
const robots=[...html.matchAll(/<meta\b[^>]*>/gi)].map(m=>m[0]).filter(t=>/\bname\s*=\s*["'\''](?:robots|googlebot)["'\'']/i.test(t)).map(t=>(t.match(/\bcontent\s*=\s*["'\'']([^"'\'']*)["'\'']/i)||[])[1]).filter(Boolean);
const canonicalTag=([...html.matchAll(/<link\b[^>]*>/gi)].map(m=>m[0]).find(t=>/\brel\s*=\s*["'\''][^"'\'']*\bcanonical\b/i.test(t))||"");
const canonical=(canonicalTag.match(/\bhref\s*=\s*["'\'']([^"'\'']+)["'\'']/i)||[])[1]||null;
const blockers=[];
if(meta.status>=400)blockers.push("HTTP status "+meta.status);
if(robots.some(x=>/\bnoindex\b/i.test(x)))blockers.push("meta robots contains noindex");
if(xrobots&&/\bnoindex\b/i.test(xrobots))blockers.push("X-Robots-Tag contains noindex");
console.log(JSON.stringify({...meta,canonical,metaRobots:robots,xRobotsTag:xrobots,blockers},null,2));
' "$meta" "$headers" "$body_file"
    rm -f "$headers" "$body_file"
    ;;

  help|-h|--help)
    grep -E '^  [a-z][a-z|-]*(\|[a-z][a-z|-]*)*\)' "$0" \
      | sed -E 's/^  //; s/\).*//; s/\|/\n/g'
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    echo "Run: $0 help" >&2
    exit 1
    ;;
esac
