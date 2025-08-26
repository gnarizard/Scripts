#!/usr/bin/env bash
# fingerprinter.sh — ultra-light web fingerprinting via curl
# Usage:
#   export DOMAIN=example.com
#   ./fingerprinter.sh                 # defaults to http://DOMAIN:80/
#   ./fingerprinter.sh -p 8080         # override port
#   (optional) export SCHEME=https     # use https
# Notes: read-only probes; outputs Markdown to stdout.

set -euo pipefail

# ------------- config (ENV ONLY) -------------
SCHEME="${SCHEME:-http}"
HOST="${DOMAIN:-${IP:-}}"
PORT="${PORT:-80}"                # default to 80 if not set
TIMEOUT=8
MAX_ASSETS=12
ENGINE_PROBES=18                 # cap engine endpoint guesses
CRAWL_PAGES=6                    # depth-1 pages to fetch (links found on /)
UA="webfp/0.4 (+read-only curl probes)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# ------------- arg parsing (port override) -------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--port)
      if [[ -n "${2-}" ]]; then PORT="$2"; shift 2; else echo "[-] Missing value for $1" >&2; exit 1; fi
      ;;
    -h|--help)
      echo "Usage: DOMAIN=example.com [SCHEME=http|https] ./fingerprinter.sh [-p PORT]" >&2
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

# ------------- require env vars -------------
if [[ -z "${HOST}" ]]; then
  echo "[-] Please export DOMAIN (or IP) before running." >&2
  echo "    export DOMAIN=example.com" >&2
  echo "    ./fingerprinter.sh [-p 8080]" >&2
  exit 1
fi

# endpoints/keywords to try (lightweight)
COMMON_ROOTS=( api v1 v2 graphql )
ENGINE_KEYS=( eval execute exec script javascript js sandbox vm render template tpl parse parser expr expression compute calc rule rules )

# regexes to grep in content
ENGINE_RX='js2py|pyimport|evaljs|JsException|JsObjectWrapper|quickjs|duktape|vm2|contextify|sandbox|isolate|nashorn|graal'
LIB_RX='js2py|quickjs|duktape|vm2|contextify|jinja2|mako|twig|blade|handlebars|mustache|ejs|pug|nunjucks|pydantic|marshmallow|express|koa|hapi|fastify|starlette|werkzeug|flask|django|falcon|rails|laravel|spring|asp\.?net|\.AspNetCore|undertow|jetty|coyote|gunicorn|uvicorn|hypercorn'
VER_RX='(version|ver|ng-version|x-aspnet-version)[\"\x27=: ]+([0-9]+\.[0-9.]+)'

# normalize base URL (hide default ports)
default_port() { [[ "$1" == "https" ]] && echo 443 || echo 80; }
if [[ "$PORT" == "$(default_port "$SCHEME")" ]]; then
  BASE="${SCHEME}://${HOST}/"
else
  BASE="${SCHEME}://${HOST}:${PORT}/"
fi

# ------------- helpers -------------
curl_head() { curl -ksS -m "$TIMEOUT" -A "$UA" -I "$1"; }
curl_get()  { curl -ksS -m "$TIMEOUT" -A "$UA" -D "$2.hdr" -o "$2.body" -w "%{http_code}" "$1"; }
curl_get_nc(){ curl -ksS -m "$TIMEOUT" -A "$UA" -H 'Cache-Control: no-cache' -D "$2.hdr" -o "$2.body" -w "%{http_code}" "$1"; }
curl_post() { curl -ksS -m "$TIMEOUT" -A "$UA" -D "$3.hdr" -o "$3.body" -H "$2" --data-binary @"$3.data" -w "%{http_code}" "$1"; }
curl_post_json() { curl -ksS -m "$TIMEOUT" -A "$UA" -D "$3.hdr" -o "$3.body" -H 'Content-Type: application/json' -d "$2" -w "%{http_code}" "$1"; }
curl_options_headers() { curl -ksS -m "$TIMEOUT" -A "$UA" -X OPTIONS -D "$1" -o /dev/null "$BASE"; }

abspath() {
  local url="$1"
  if [[ "$url" =~ ^https?:// ]]; then echo "$url"; else
    if [[ "$url" == /* ]]; then echo "${BASE%/}$url"; else echo "${BASE}$url"; fi
  fi
}

title_of() { grep -i -o '<title[^>]*>[^<]*' "$1" | sed -E 's/.*>//' | head -n1; }

print_kv() { printf "**%s:** %s\n" "$1" "$2"; }
uniq_lines() { awk '!seen[$0]++'; }

# ------------- data stores -------------
declare -A HEADERS
declare -A HEADERS_SEC=()
COOKIES=()
COOKIE_FLAGS=()
ASSETS=()
LINKS=()
ERRS_KEYS=()
declare -A ERRS_BODY
SOURCEMAPS=()
SOURCEMAPS_CONTENT=()
VERSION_HINTS=()
HITS_HEADER=()
HITS_COOKIE=()
ENGINE_MARKERS=()
JS_URLS=()

# node inference flags
SOFT_NODE_CLUE=0
NODE_HARD_HINT=0

# ------------- base fetch -------------
base_id="$TMPDIR/base"
code=$(curl_get "$BASE" "$base_id") || true
mapfile -t hdr_lines < <(cat "$base_id.hdr" 2>/dev/null || true)
for h in "${hdr_lines[@]}"; do
  h="${h%%$'\r'}"
  if [[ "$h" =~ ^[Ss]erver: ]]; then
    HEADERS[server]="${h#*: }"
  elif [[ "$h" =~ ^[Xx]-[Pp]owered-[Bb]y: ]]; then
    HEADERS[x_powered_by]="${h#*: }"
    if echo "${HEADERS[x_powered_by]}" | grep -Eqi 'express|koa|hapi|fastify|nest'; then NODE_HARD_HINT=1; fi
  elif [[ "$h" =~ ^[Dd]ate: ]]; then
    HEADERS[date]="${h#*: }"
  elif [[ "$h" =~ ^[Cc]ontent-[Tt]ype: ]]; then
    HEADERS[content_type]="${h#*: }"
  elif [[ "$h" =~ ^[Ss]et-[Cc]ookie: ]]; then
    ck=${h#*: }
    while IFS= read -r part; do
      nm=$(echo "$part" | cut -d';' -f1 | sed 's/^[ ]*//')
      [[ "$nm" == *=* ]] && COOKIES+=("$nm")
      if echo "$nm" | grep -qi '^connect\.sid='; then NODE_HARD_HINT=1; fi
    done < <(echo "$ck" | tr -d '\r' | tr ',' '\n')
  fi
done

TITLE="$(title_of "$base_id.body" 2>/dev/null || true)"
[[ -n "${HEADERS[server]:-}" ]] && HITS_HEADER+=("server:${HEADERS[server]}")

# ------------- OPTIONS + security headers + cookie flags -------------
opt_hdr="$TMPDIR/opts.hdr"
if curl_options_headers "$opt_hdr"; then
  ALLOW_METHODS="$(grep -i '^Allow:' "$opt_hdr" | sed 's/^Allow:[ ]*//I' | tr -d '\r' | head -n1 || true)"
fi

SEC_HEADERS=( \
  content-security-policy x-frame-options strict-transport-security \
  cross-origin-opener-policy cross-origin-embedder-policy \
  cross-origin-resource-policy referrer-policy permissions-policy
)
for k in "${SEC_HEADERS[@]}"; do
  # try GET headers first, then OPTIONS headers
  v="$(grep -i "^$k:" "$base_id.hdr" 2>/dev/null | sed -E 's/^[^:]+:[ ]*//' | head -n1 || true)"
  [[ -z "$v" && -s "$opt_hdr" ]] && v="$(grep -i "^$k:" "$opt_hdr" 2>/dev/null | sed -E 's/^[^:]+:[ ]*//' | head -n1 || true)"
  [[ -n "$v" ]] && HEADERS_SEC["$k"]="$v"
done

# first-party cookie flags
while IFS= read -r setck; do
  name="$(echo "$setck" | cut -d';' -f1 | sed 's/^[ ]*//')"
  flags=""
  IFS=';' read -ra parts <<<"$(echo "$setck" | sed 's/^.*;//')"
  for p in "${parts[@]}"; do
    p_trim="$(echo "$p" | sed 's/^[ ]*//' )"
    p_low="$(echo "$p_trim" | tr '[:upper:]' '[:lower:]')"
    case "$p_low" in
      httponly) flags="$flags;HttpOnly";;
      secure) flags="$flags;Secure";;
      samesite=*) flags="$flags;SameSite=$(echo "$p_trim" | cut -d= -f2)";;
    esac
  done
  COOKIE_FLAGS+=("$name$flags")
done < <(grep -i '^Set-Cookie:' "$base_id.hdr" 2>/dev/null | sed 's/^Set-Cookie:[ ]*//I' || true)

# ------------- parse links & assets (homepage only) -------------
if command -v grep >/dev/null; then
  while IFS= read -r attr; do
    u="${attr#href=\"}"; u="${u#src=\"}"; u="${u%\"}"
    [[ -z "$u" ]] && continue
    full=$(abspath "$u")
    if [[ "$u" =~ \.js($|\?)|\.css($|\?) ]]; then ASSETS+=("$full"); fi
    if [[ "$full" == ${BASE%/}/* ]]; then LINKS+=("$full"); fi
  done < <(grep -Eoi '(href|src)="[^"]+"' "$base_id.body" 2>/dev/null | head -n 400)
fi

ASSETS=($(printf "%s\n" "${ASSETS[@]}" | uniq_lines | head -n "$MAX_ASSETS"))
LINKS=($(printf "%s\n" "${LINKS[@]}" | uniq_lines | head -n "$CRAWL_PAGES"))

# ------------- 404 + robots + sitemap + favicon -------------
z404_id="$TMPDIR/404"; curl_get "${BASE}this/definitely/404" "$z404_id" >/dev/null || true
robots_id="$TMPDIR/robots"; curl_get "${BASE}robots.txt" "$robots_id" >/dev/null || true
sitemap_id="$TMPDIR/sitemap"; curl_get "${BASE}sitemap.xml" "$sitemap_id" >/dev/null || true
if [[ -s "$sitemap_id.body" ]]; then
  while IFS= read -r loc; do
    full=$(abspath "$loc"); [[ "$full" == ${BASE%/}/* ]] && LINKS+=("$full")
  done < <(grep -Eo '<loc>[^<]+' "$sitemap_id.body" 2>/dev/null | sed 's/<loc>//' | head -n 100)
fi
LINKS=($(printf "%s\n" "${LINKS[@]}" | uniq_lines | head -n "$CRAWL_PAGES"))

fav_id="$TMPDIR/fav"; curl_get "${BASE}favicon.ico" "$fav_id" >/dev/null || true
FAV_SHA=""; if [[ -s "$fav_id.body" && "$(command -v sha1sum)" ]]; then FAV_SHA=$(sha1sum "$fav_id.body" | awk '{print $1}'); fi

# ------------- scan assets for hints + sourcemaps + JS endpoints -------------
sm_count=0
for a in "${ASSETS[@]}"; do
  id="$TMPDIR/a$(echo -n "$a" | md5sum | cut -d' ' -f1)"
  curl_get_nc "$a" "$id" >/dev/null || true
  [[ -s "$id.body" ]] || continue

  # soft Node clue
  if grep -Eq 'process\.env|globalThis\.process|module\.exports|(^|[^A-Za-z])require\(' "$id.body"; then
    SOFT_NODE_CLUE=1
  fi

  # version hints
  while IFS= read -r m; do
    v=$(echo "$m" | sed -E "s/$VER_RX/\2/i"); [[ -n "$v" ]] && VERSION_HINTS+=("$v")
  done < <(grep -Eio "$VER_RX" "$id.body" 2>/dev/null || true)

  # sourcemap URL
  if grep -Eq '#[@]\s*sourceMappingURL=' "$id.body"; then
    sm=$(grep -Eo '#[@]\s*sourceMappingURL=\S+' "$id.body" | awk -F= '{print $2}' | head -n1)
    smu=$(abspath "$(dirname "$a")/$sm")
    sm_id="$TMPDIR/sm$(echo -n "$smu" | md5sum | cut -d' ' -f1)"
    curl_get "$smu" "$sm_id" >/dev/null || true
    if [[ -s "$sm_id.body" && $sm_count -lt 3 ]]; then
      SOURCEMAPS+=("$smu")
      SOURCEMAPS_CONTENT+=("$(head -c 400 "$sm_id.body")")
      ((sm_count++))
    fi
  fi

  # JS-discussed endpoints (fetch/axios/XHR)
  while IFS= read -r u; do
    JS_URLS+=("$(abspath "$u")")
  done < <(grep -Eo "fetch\(['\"][^'\"]+|axios\.(get|post|put|patch|delete)\(['\"][^'\"]+|XMLHttpRequest\(\)\.open\(['\"][A-Z]+['\"],\s*['\"][^'\"]+" "$id.body" 2>/dev/null \
            | sed -E "s/.*\(['\"]([^'\"]+).*/\1/" | head -n 80)
done
JS_URLS=($(printf "%s\n" "${JS_URLS[@]}" | uniq_lines))

# ------------- engine probes (light) -------------
CANDS=()
for r in "${COMMON_ROOTS[@]}"; do CANDS+=("${BASE}${r}/"); done
for k in "${ENGINE_KEYS[@]}"; do
  CANDS+=("${BASE}${k}" "${BASE}api/${k}" "${BASE}v1/${k}")
done
for u in "${LINKS[@]}" "${JS_URLS[@]}"; do
  low=$(echo "$u" | tr '[:upper:]' '[:lower:]')
  for k in "${ENGINE_KEYS[@]}" "${COMMON_ROOTS[@]}"; do
    if [[ "$low" == *"/$k" || "$low" == *"/$k/" || "$low" == *"/$k?"* ]]; then CANDS+=("$u"); fi
  done
done
CANDS=($(printf "%s\n" "${CANDS[@]}" | uniq_lines | head -n "$ENGINE_PROBES"))

probe_json_bad() {
  local url="$1"; local id="$TMPDIR/p$(echo -n "$url" | md5sum | cut -d' ' -f1)"
  curl_post_json "$url" "{" "$id" >/dev/null || true
  if grep -Eqi "$ENGINE_RX|$LIB_RX" "$id.body" 2>/dev/null; then
    ERRS_KEYS+=("engine_badjson:$url"); ERRS_BODY["engine_badjson:$url"]="$(head -c 600 "$id.body")"
  fi
}
probe_json_keys() {
  local url="$1"
  for k in script code expr; do
    local id="$TMPDIR/p$(echo -n "$url$k" | md5sum | cut -d' ' -f1)"
    curl_post_json "$url" "{\"$k\":\"(\"}" "$id" >/dev/null || true
    if grep -Eqi "$ENGINE_RX|$LIB_RX" "$id.body" 2>/dev/null; then
      ERRS_KEYS+=("engine_json_${k}:$url"); ERRS_BODY["engine_json_${k}:$url"]="$(head -c 600 "$id.body")"; break
    fi
  done
}
probe_raw_js() {
  local url="$1"
  for ct in "application/javascript" "text/javascript" "text/plain"; do
    local id="$TMPDIR/p$(echo -n "$url$ct" | md5sum | cut -d' ' -f1)"
    echo "(" > "$id.data"
    curl_post "$url" "Content-Type: $ct" "$id" >/dev/null || true
    if grep -Eqi "$ENGINE_RX|$LIB_RX" "$id.body" 2>/dev/null; then
      ERRS_KEYS+=("engine_raw_${ct}:$url"); ERRS_BODY["engine_raw_${ct}:$url"]="$(head -c 600 "$id.body")"; break
    fi
  done
}
probe_get_json() {
  local url="$1"; local id="$TMPDIR/g$(echo -n "$url" | md5sum | cut -d' ' -f1)"
  curl -ksS -m "$TIMEOUT" -A "$UA" -H "Accept: application/json" -D "$id.hdr" -o "$id.body" "$url" >/dev/null || true
  if grep -Eqi "$ENGINE_RX|$LIB_RX" "$id.body" 2>/dev/null; then
    ERRS_KEYS+=("engine_get:$url"); ERRS_BODY["engine_get:$url"]="$(head -c 600 "$id.body")"
  fi
}

for url in "${CANDS[@]}"; do
  probe_get_json "$url"
  probe_json_bad "$url"
  probe_json_keys "$url"
  probe_raw_js "$url"
done

# collect engine markers from error bodies
for k in "${ERRS_KEYS[@]}"; do
  if echo "${ERRS_BODY[$k]}" | grep -Eqi "$ENGINE_RX"; then ENGINE_MARKERS+=("$k"); fi
  if echo "${ERRS_BODY[$k]}" | grep -Eqi 'vm2|contextify'; then NODE_HARD_HINT=1; fi
done

# ------------- cookies / headers -> hits -------------
[[ -n "${HEADERS[server]:-}" ]] && HITS_HEADER+=("server:${HEADERS[server]}")
for c in "${COOKIES[@]}"; do
  low=$(echo "$c" | tr '[:upper:]' '[:lower:]')
  case "$low" in
    csrftoken=*|sessionid=*|laravel_session=*|xsrf-token=*|connect.sid=*|.aspnetcore*|jsessionid=*|rack.session* )
      HITS_COOKIE+=("$c");;
  esac
done

# ------------- quick hypotheses (simple rules) -------------
HYPOS=()
if printf "%s\n" "${ERRS_BODY[@]}" "${SOURCEMAPS_CONTENT[@]}" | grep -Eqi 'js2py';   then HYPOS+=("engine:js2py [high]"); fi
if printf "%s\n" "${ERRS_BODY[@]}" "${SOURCEMAPS_CONTENT[@]}" | grep -Eqi 'quickjs'; then HYPOS+=("engine:quickjs [med]");  fi
if grep -Eqi 'gunicorn|uvicorn|hypercorn' "$base_id.hdr"; then HYPOS+=("server:python_asgi_wsgi [med]"); fi
if [[ $NODE_HARD_HINT -eq 1 ]]; then HYPOS+=("framework:nodejs [high]"); fi
mapfile -t HYPOS < <(printf '%s\n' "${HYPOS[@]}" | uniq_lines)

# ------------- context (offline) -------------
RAT=(); NHUNTS=(); QUERIES=(); CVESEED=()
[[ -n "${HEADERS[server]:-}" ]] && RAT+=("Headers suggest: server: ${HEADERS[server]}")
[[ -n "${HEADERS[x_powered_by]:-}" ]] && RAT+=("X-Powered-By: ${HEADERS[x_powered_by]}")
if [[ "${#HITS_COOKIE[@]}" -gt 0 ]]; then
  cookie_names=$(printf "%s\n" "${HITS_COOKIE[@]}" | sed 's/;.*//' | awk -F= '{print $1}' | paste -sd' ' -)
  RAT+=("Cookies seen: ${cookie_names}")
fi
if [[ "${#ENGINE_MARKERS[@]}" -gt 0 ]]; then
  markers=$(printf "%s\n" "${ENGINE_MARKERS[@]}" | sed 's/engine_[^:]*://g' | paste -sd' ' -)
  RAT+=("Engine markers: ${markers}")
fi
if [[ $SOFT_NODE_CLUE -eq 1 && $NODE_HARD_HINT -eq 0 ]]; then
  RAT+=("Frontend bundles reference Node-like shims (soft hint only).")
fi

# version hints from base html
if [[ -s "$base_id.body" ]]; then
  while IFS= read -r m; do
    v=$(echo "$m" | sed -E "s/$VER_RX/\2/i"); [[ -n "$v" ]] && VERSION_HINTS+=("$v")
  done < <(grep -Eio "$VER_RX" "$base_id.body" 2>/dev/null || true)
fi
VERSION_HINTS=($(printf "%s\n" "${VERSION_HINTS[@]}" | uniq_lines))

# enrichers (unchanged from your working copy)
has_hypo() { local needle="$1"; for h in "${HYPOS[@]}"; do base="${h%% *}"; [[ "$base" == "$needle" ]] && return 0; done; return 1; }
add_unique_line(){ local what="$1"; shift; local line="$*"; case "$what" in RAT)RAT+=("$line");;NHUNTS)NHUNTS+=("$line");;QUERIES)QUERIES+=("$line");;CVESEED)CVESEED+=("$line");;esac; }

if has_hypo "engine:js2py"; then
  add_unique_line RAT "engine:js2py: Python-side JS eval; sandbox escapes have existed."
  add_unique_line NHUNTS "Look for endpoints that accept raw JS (Content-Type: text/javascript or application/javascript)."
  add_unique_line NHUNTS "Trigger small syntax errors to surface 'PyJsException', 'pyimport', or 'evaljs' in traces."
  add_unique_line QUERIES "js2py sandbox escape"
  add_unique_line QUERIES "js2py pyimport evaljs"
  add_unique_line QUERIES "js2py vulnerability CVE"
  add_unique_line CVESEED "CVE-2024-28397"
fi
if has_hypo "engine:quickjs"; then
  add_unique_line RAT "engine:quickjs: embedded JS engine (often via wrappers/bindings)."
  add_unique_line NHUNTS "Probe raw-JS POSTs; check for QuickJS-looking stack frames in error bodies."
  add_unique_line NHUNTS "Exercise timeouts/quotas with small loops (read-only) to see if isolation breaks."
  add_unique_line QUERIES "quickjs sandbox escape"
  add_unique_line QUERIES "quickjs RCE CVE"
fi
if grep -q "^engine:" <(printf "%s\n" "${HYPOS[@]}" | sed 's/ \[.*\]$//'); then
  add_unique_line NHUNTS "Map any /eval|/execute|/expr|/script endpoints; prefer JSON with {expr:'('} to elicit parser traces."
  add_unique_line NHUNTS "Try text/javascript vs application/json bodies; compare error signatures."
  add_unique_line QUERIES "server-side javascript engine sandbox"
fi
if has_hypo "server:python_asgi_wsgi"; then
  add_unique_line RAT "Python ASGI/WSGI backend (gunicorn/uvicorn/hypercorn)."
  add_unique_line NHUNTS "Correlate cookies (sessionid/csrftoken) to distinguish Django vs Flask."
  add_unique_line QUERIES "python asgi wsgi identify framework"
fi
if has_hypo "framework:flask"; then
  add_unique_line RAT "framework:flask: Jinja2 SSTI risks if misused."
  add_unique_line NHUNTS "Check error pages; harmless '{{7*7}}' in reflected inputs (read-only)."
  add_unique_line QUERIES "Flask Jinja2 SSTI cheat sheet"
fi
if has_hypo "framework:django"; then
  add_unique_line RAT "framework:django: CSRF baked-in; urls like /admin/, cookies 'csrftoken'/'sessionid'."
  add_unique_line NHUNTS "Probe /admin/ (200/302/403 is still a fingerprint)."
  add_unique_line NHUNTS "Look for 'csrfmiddlewaretoken' in forms; confirm version via /static/admin/ assets."
  add_unique_line QUERIES "Django version fingerprint static admin"
fi
if has_hypo "framework:nodejs"; then
  add_unique_line RAT "framework:nodejs: check X-Powered-By (express/koa/fastify) and 'connect.sid' cookies."
  add_unique_line NHUNTS "If a 'code-run' endpoint exists, differentiate engines: send small JS to reveal 'typeof process'."
  add_unique_line NHUNTS "Look for vm2/contextify strings in error bodies (indicates sandboxed Node)."
  add_unique_line QUERIES "express identify headers"
  add_unique_line QUERIES "vm2 sandbox escape patterns"
fi
add_unique_line NHUNTS "Check security headers via OPTIONS / and GET /: CSP, X-Frame-Options, HSTS, COOP/COEP/CORP."
add_unique_line NHUNTS "List allowed methods on likely endpoints; note unexpected PUT/PATCH/DELETE."
add_unique_line QUERIES "web app fingerprinting checklist"
add_unique_line QUERIES "security headers best practices"

for h in "${HYPOS[@]}"; do t="${h#*:}"; t="${t%% *}"; QUERIES+=("$t vulnerability CVE"); done
mapfile -t QUERIES < <(printf '%s\n' "${QUERIES[@]}" | awk 'NF' | uniq_lines | head -n 8)
mapfile -t NHUNTS  < <(printf '%s\n' "${NHUNTS[@]}"  | awk 'NF' | uniq_lines | head -n 8)
mapfile -t RAT     < <(printf '%s\n' "${RAT[@]}"     | awk 'NF' | uniq_lines | head -n 6)
mapfile -t CVESEED < <(printf '%s\n' "${CVESEED[@]}" | awk 'NF' | uniq_lines | head -n 8)

# ------------- CMS quick targets -------------
CMS_HITS=()

# Drupal / Backdrop
if curl -fsS "${BASE}" | grep -qi 'meta name="generator"'; then CMS_HITS+=("drupal/backdrop: meta generator tag"); fi
if curl -sI "${BASE}" | grep -qi '^X-Generator'; then CMS_HITS+=("drupal/backdrop: X-Generator header"); fi
if curl -fsS "${BASE}core/CHANGELOG.txt" | grep -qi drupal; then CMS_HITS+=("drupal: core/CHANGELOG.txt exposed"); fi
if curl -fsS "${BASE}CHANGELOG.txt" | grep -qi drupal; then CMS_HITS+=("drupal: 7.x CHANGELOG.txt exposed"); fi

# WordPress
if curl -fsS "${BASE}readme.html" | grep -qi wordpress; then CMS_HITS+=("wordpress: readme.html"); fi
if curl -fsS "${BASE}wp-includes/version.php" | grep -q '\$wp_version'; then CMS_HITS+=("wordpress: wp-includes/version.php"); fi

# Joomla
if curl -fsS "${BASE}README.txt" | grep -qi joomla; then CMS_HITS+=("joomla: README.txt"); fi
if curl -fsS "${BASE}language/en-GB/en-GB.xml" | grep -qi version; then CMS_HITS+=("joomla: language XML version"); fi

# Generic PHP apps (version hints)
php_ver=$(curl -fsS "${BASE}" | grep -Eio 'v[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -Vu | tail -n1 || true)
if [[ -n "$php_ver" ]]; then CMS_HITS+=("generic-php: version string $php_ver"); fi


# ------------- report (Markdown) -------------
echo "# Web Fingerprinter"
print_kv "Target" "$BASE"
[[ -n "$TITLE" ]] && print_kv "Title" "$TITLE"
[[ -n "${HEADERS[server]:-}" ]] && print_kv "Server" "${HEADERS[server]}"
[[ -n "${HEADERS[x_powered_by]:-}" ]] && print_kv "X-Powered-By" "${HEADERS[x_powered_by]}"
[[ -n "${HEADERS[content_type]:-}" ]] && print_kv "Content-Type" "${HEADERS[content_type]}"
[[ -n "$FAV_SHA" ]] && print_kv "Favicon (sha1)" "$FAV_SHA"
[[ -n "${ALLOW_METHODS:-}" ]] && print_kv "Allow (OPTIONS /)" "$ALLOW_METHODS"

if [[ ${HEADERS_SEC+set} == set ]] && ((${#HEADERS_SEC[@]})); then
  echo -e "\n**Security headers (GET/OPTIONS):**"
  for k in "${!HEADERS_SEC[@]}"; do
    printf "- %s: %s\n" "$k" "${HEADERS_SEC[$k]}"
  done
fi


if [[ "${#COOKIES[@]}" -gt 0 ]]; then
  names=$(printf "%s\n" "${COOKIES[@]}" | sed 's/;.*//' | awk -F= '{print $1}' | paste -sd' ' -)
  echo -e "\n**Cookies (names):** $names"
fi

if [[ "${#COOKIE_FLAGS[@]}" -gt 0 ]]; then
  echo -e "\n**Cookie flags (first-party):**"
  for c in "${COOKIE_FLAGS[@]}"; do echo "- $c"; done
fi

if [[ "${#ASSETS[@]}" -gt 0 ]]; then
  echo -e "\n**Assets (sample):**"
  for a in "${ASSETS[@]}"; do echo "- $a"; done
fi

if [[ "${#SOURCEMAPS[@]}" -gt 0 ]]; then
  echo -e "\n**Sourcemaps (sample):**"
  for i in "${!SOURCEMAPS[@]}"; do echo "- ${SOURCEMAPS[$i]}"; done
fi

if [[ "${#VERSION_HINTS[@]}" -gt 0 ]]; then
  echo -e "\n**Version hints:** $(printf "%s " "${VERSION_HINTS[@]}")"
fi

if [[ "${#JS_URLS[@]}" -gt 0 ]]; then
  echo -e "\n**JS Endpoints (from frontend):**"
  for u in "${JS_URLS[@]}"; do echo "- $u"; done
fi

if [[ "${#CMS_HITS[@]}" -gt 0 ]]; then
  echo -e "\n**CMS quick hits:**"
  for c in "${CMS_HITS[@]}"; do echo "- $c"; done
fi


if [[ "${#HYPOS[@]}" -gt 0 ]]; then
  echo -e "\n## Hypotheses"
  for h in "${HYPOS[@]}"; do echo "- $h"; done
fi

if [[ "${#ERRS_KEYS[@]}" -gt 0 ]]; then
  echo -e "\n## Error snippets (engine/context leaks)"
  for k in "${ERRS_KEYS[@]}"; do
    echo "- **$k**"
    echo '```'
    echo "${ERRS_BODY[$k]}"
    echo '```'
  done
fi

if [[ "${#RAT[@]}" -gt 0 || "${#NHUNTS[@]}" -gt 0 || "${#QUERIES[@]}" -gt 0 || "${#CVESEED[@]}" -gt 0 ]]; then
  echo -e "\n## Context"
  if [[ "${#RAT[@]}" -gt 0 ]]; then
    echo "**Rationale**"
    for r in "${RAT[@]}"; do echo "- $r"; done
  fi
  # (keep these commented to stay lean)
  # if [[ "${#NHUNTS[@]}" -gt 0 ]]; then
  #   echo -e "\n**Next hunts**"
  #   for h in "${NHUNTS[@]}"; do echo "- $h"; done
  # fi
  # if [[ "${#QUERIES[@]}" -gt 0 ]]; then
  #   echo -e "\n**Search queries**"
  #   for q in "${QUERIES[@]}"; do echo "- $q"; done
  # fi
  if [[ "${#CVESEED[@]}" -gt 0 ]]; then
    echo -e "\n**CVE seeds**"
    for c in "${CVESEED[@]}"; do echo "- $c"; done
  fi
fi

echo
