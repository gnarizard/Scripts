#!/usr/bin/env bash
# fingerprinter.sh — ultra-light web fingerprinting via curl (ENV ONLY)
# Usage:
#   export DOMAIN=example.com; export PORT=8000
#   ./fingerprinter.sh                # defaults to http://DOMAIN:PORT/
#   (optional) export SCHEME=https    # use https
# Notes: read-only probes; outputs Markdown to stdout.

set -euo pipefail

# ------------- config (ENV ONLY) -------------
SCHEME="${SCHEME:-http}"
HOST="${DOMAIN:-${IP:-}}"
PORT="${PORT:-}"
TIMEOUT=8
MAX_ASSETS=12
ENGINE_PROBES=18            # cap engine endpoint guesses
CRAWL_PAGES=6               # depth-1 pages to fetch (links found on /)
UA="webfp/0.4 (+read-only curl probes)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Require env vars
if [[ -z "${HOST}" || -z "${PORT}" ]]; then
  echo "[-] Please export DOMAIN (or IP) and PORT before running." >&2
  echo "    export DOMAIN=codetwo.htb; export PORT=8000" >&2
  echo "    ./fingerprinter.sh" >&2
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
curl_post() { curl -ksS -m "$TIMEOUT" -A "$UA" -D "$3.hdr" -o "$3.body" -H "$2" --data-binary @"$3.data" -w "%{http_code}" "$1"; }
curl_post_json() { curl -ksS -m "$TIMEOUT" -A "$UA" -D "$3.hdr" -o "$3.body" -H 'Content-Type: application/json' -d "$2" -w "%{http_code}" "$1"; }
curl_options() { curl -ksS -m "$TIMEOUT" -A "$UA" -X OPTIONS -i "$1"; }

abspath() { # resolve absolute URL
  local url="$1"
  if [[ "$url" =~ ^https?:// ]]; then echo "$url"; else
    if [[ "$url" == /* ]]; then echo "${BASE%/}$url"; else echo "${BASE}$url"; fi
  fi
}

title_of() { grep -i -o '<title[^>]*>[^<]*' "$1" | sed -E 's/.*>//' | head -n1; }

hr() { echo -e "\n---\n"; }
print_kv() { printf "**%s:** %s\n" "$1" "$2"; }
uniq_lines() { awk '!seen[$0]++'; }

# ------------- data stores -------------
declare -A HEADERS
COOKIES=()
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

# ------------- base fetch -------------
base_id="$TMPDIR/base"
code=$(curl_get "$BASE" "$base_id") || true
mapfile -t hdr_lines < <(cat "$base_id.hdr" 2>/dev/null || true)
for h in "${hdr_lines[@]}"; do
  h="${h%%$'\r'}"
  if [[ "$h" =~ ^[Ss]erver: ]]; then HEADERS[server]="${h#*: }"
  elif [[ "$h" =~ ^[Dd]ate: ]]; then HEADERS[date]="${h#*: }"
  elif [[ "$h" =~ ^[Cc]ontent-[Tt]ype: ]]; then HEADERS[content_type]="${h#*: }"
  elif [[ "$h" =~ ^[Ss]et-[Cc]ookie: ]]; then
    ck=${h#*: }
    while IFS= read -r part; do
      nm=$(echo "$part" | cut -d';' -f1 | sed 's/^[ ]*//')
      [[ "$nm" == *=* ]] && COOKIES+=("$nm")
    done < <(echo "$ck" | tr -d '\r' | tr ',' '\n')
  fi
done

TITLE="$(title_of "$base_id.body" 2>/dev/null || true)"
[[ -n "${HEADERS[server]:-}" ]] && HITS_HEADER+=("server:${HEADERS[server]}")

# ------------- parse links & assets (homepage only) -------------
if command -v grep >/dev/null; then
  while IFS= read -r attr; do
    u="${attr#href=\"}"; u="${u#src=\"}"; u="${u%\"}"
    [[ -z "$u" ]] && continue
    full=$(abspath "$u")
    # assets
    if [[ "$u" =~ \.js($|\?)|\.css($|\?) ]]; then
      ASSETS+=("$full")
    fi
    # internal links (for depth-1)
    if [[ "$full" == ${BASE%/}/* ]]; then
      LINKS+=("$full")
    fi
  done < <(grep -Eoi '(href|src)="[^"]+"' "$base_id.body" 2>/dev/null | head -n 400)
fi

ASSETS=($(printf "%s\n" "${ASSETS[@]}" | uniq_lines | head -n "$MAX_ASSETS"))
LINKS=($(printf "%s\n" "${LINKS[@]}" | uniq_lines | head -n "$CRAWL_PAGES"))

# ------------- 404 + robots + sitemap + favicon -------------
z404_id="$TMPDIR/404"
curl_get "${BASE}this/definitely/404" "$z404_id" >/dev/null || true

robots_id="$TMPDIR/robots"
curl_get "${BASE}robots.txt" "$robots_id" >/dev/null || true

sitemap_id="$TMPDIR/sitemap"
curl_get "${BASE}sitemap.xml" "$sitemap_id" >/dev/null || true
if [[ -s "$sitemap_id.body" ]]; then
  while IFS= read -r loc; do
    full=$(abspath "$loc")
    [[ "$full" == ${BASE%/}/* ]] && LINKS+=("$full")
  done < <(grep -Eo '<loc>[^<]+' "$sitemap_id.body" 2>/dev/null | sed 's/<loc>//' | head -n 100)
fi
LINKS=($(printf "%s\n" "${LINKS[@]}" | uniq_lines | head -n "$CRAWL_PAGES"))

fav_id="$TMPDIR/fav"
curl_get "${BASE}favicon.ico" "$fav_id" >/dev/null || true
FAV_SHA=""
if [[ -s "$fav_id.body" && "$(command -v sha1sum)" ]]; then
  FAV_SHA=$(sha1sum "$fav_id.body" | awk '{print $1}')
fi

# ------------- scan assets for hints + sourcemaps + JS endpoints -------------
sm_count=0
for a in "${ASSETS[@]}"; do
  id="$TMPDIR/a$(echo -n "$a" | md5sum | cut -d' ' -f1)"
  curl_get "$a" "$id" >/dev/null || true
  [[ -s "$id.body" ]] || continue
  # version hints
  while IFS= read -r m; do
    v=$(echo "$m" | sed -E "s/$VER_RX/\2/i")
    [[ -n "$v" ]] && VERSION_HINTS+=("$v")
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
# build candidates
CANDS=()
for r in "${COMMON_ROOTS[@]}"; do CANDS+=("${BASE}${r}/"); done
for k in "${ENGINE_KEYS[@]}"; do
  CANDS+=("${BASE}${k}")
  CANDS+=("${BASE}api/${k}")
  CANDS+=("${BASE}v1/${k}")
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
    ERRS_KEYS+=("engine_badjson:$url")
    ERRS_BODY["engine_badjson:$url"]="$(head -c 600 "$id.body")"
  fi
}
probe_json_keys() {
  local url="$1"
  for k in script code expr; do
    local id="$TMPDIR/p$(echo -n "$url$k" | md5sum | cut -d' ' -f1)"
    curl_post_json "$url" "{\"$k\":\"(\"}" "$id" >/dev/null || true
    if grep -Eqi "$ENGINE_RX|$LIB_RX" "$id.body" 2>/dev/null; then
      ERRS_KEYS+=("engine_json_${k}:$url")
      ERRS_BODY["engine_json_${k}:$url"]="$(head -c 600 "$id.body")"
      break
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
      ERRS_KEYS+=("engine_raw_${ct}:$url")
      ERRS_BODY["engine_raw_${ct}:$url"]="$(head -c 600 "$id.body")"
      break
    fi
  done
}
probe_get_json() {
  local url="$1"; local id="$TMPDIR/g$(echo -n "$url" | md5sum | cut -d' ' -f1)"
  curl -ksS -m "$TIMEOUT" -A "$UA" -H "Accept: application/json" -D "$id.hdr" -o "$id.body" "$url" >/dev/null || true
  if grep -Eqi "$ENGINE_RX|$LIB_RX" "$id.body" 2>/dev/null; then
    ERRS_KEYS+=("engine_get:$url")
    ERRS_BODY["engine_get:$url"]="$(head -c 600 "$id.body")"
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
  if echo "${ERRS_BODY[$k]}" | grep -Eqi "$ENGINE_RX"; then
    ENGINE_MARKERS+=("$k")
  fi
done

# ------------- cookies / headers -> hits -------------
if [[ -n "${HEADERS[server]:-}" ]]; then
  HITS_HEADER+=("server:${HEADERS[server]}")
fi
for c in "${COOKIES[@]}"; do
  low=$(echo "$c" | tr '[:upper:]' '[:lower:]')
  case "$low" in
    csrftoken=*|sessionid=*|laravel_session=*|xsrf-token=*|connect.sid=*|.aspnetcore*|jsessionid=*|rack.session* )
      HITS_COOKIE+=("$c");;
  esac
done

# ------------- quick hypotheses (simple rules) -------------
HYPOS=()   # lines like "engine:js2py" or "framework:flask"

# engine hints (from captured error bodies or sourcemaps)
if printf "%s\n" "${ERRS_BODY[@]}" "${SOURCEMAPS_CONTENT[@]}" | grep -Eqi 'js2py';   then HYPOS+=("engine:js2py");   fi
if printf "%s\n" "${ERRS_BODY[@]}" "${SOURCEMAPS_CONTENT[@]}" | grep -Eqi 'quickjs'; then HYPOS+=("engine:quickjs"); fi

# server/framework hints from saved files
if grep -Eqi 'gunicorn|uvicorn|hypercorn' "$base_id.hdr";              then HYPOS+=("server:python_asgi_wsgi"); fi
if grep -Eqi 'flask|werkzeug'            "$base_id.body";             then HYPOS+=("framework:flask");        fi
if grep -Eqi 'django'                     "$base_id.body";             then HYPOS+=("framework:django");      fi
if grep -Eqi 'express|koa|hapi|fastify'   "$base_id.body";             then HYPOS+=("framework:nodejs");      fi

HYPOS=($(printf "%s\n" "${HYPOS[@]}" | uniq_lines))

# ------------- context (offline) -------------
RAT=()
NHUNTS=()
QUERIES=()
CVESEED=()

[[ -n "${HEADERS[server]:-}" ]] && RAT+=("Headers suggest: server: ${HEADERS[server]}")
if [[ "${#HITS_COOKIE[@]}" -gt 0 ]]; then
  cookie_names=$(printf "%s\n" "${HITS_COOKIE[@]}" | sed 's/;.*//' | awk -F= '{print $1}' | paste -sd' ' -)
  RAT+=("Cookies seen: ${cookie_names}")
fi
if [[ "${#ENGINE_MARKERS[@]}" -gt 0 ]]; then
  markers=$(printf "%s\n" "${ENGINE_MARKERS[@]}" | sed 's/engine_[^:]*://g' | paste -sd' ' -)
  RAT+=("Engine markers: ${markers}")
fi

# version hints from base html
if [[ -s "$base_id.body" ]]; then
  while IFS= read -r m; do
    v=$(echo "$m" | sed -E "s/$VER_RX/\2/i")
    [[ -n "$v" ]] && VERSION_HINTS+=("$v")
  done < <(grep -Eio "$VER_RX" "$base_id.body" 2>/dev/null || true)
fi
VERSION_HINTS=($(printf "%s\n" "${VERSION_HINTS[@]}" | uniq_lines))

# enrich by detected hypos
has_hypo() { printf "%s\n" "${HYPOS[@]}" | grep -qx "$1"; }
if has_hypo "engine:js2py"; then
  RAT+=("engine:js2py: Python-side JS eval; sandbox escapes have existed.")
  NHUNTS+=("Look for endpoints accepting raw JS (text/javascript).")
  NHUNTS+=("Trigger syntax errors to reveal 'js2py/pyimport/evaljs' in traces.")
  QUERIES+=("project: js2py docs" "keywords: js2py sandbox escape pyimport evaljs" "js2py vulnerability CVE")
  CVESEED+=("CVE-2024-28397")
fi
if has_hypo "engine:quickjs"; then
  RAT+=("engine:quickjs: Embedded JS engine; wrappers may expose eval-like endpoints.")
  NHUNTS+=("Probe raw JS bodies; check timeouts; look for QuickJS stack frames.")
  QUERIES+=("quickjs sandbox escape" "quickjs RCE CVE")
fi
if has_hypo "framework:flask"; then
  RAT+=("framework:flask: Jinja2 SSTI risks if misused.")
  NHUNTS+=("Check error pages; harmless '{{7*7}}' in reflected inputs (read-only).")
  QUERIES+=("Flask Jinja2 SSTI cheat sheet")
fi
if has_hypo "server:python_asgi_wsgi"; then
  RAT+=("Python ASGI/WSGI backend (gunicorn/uvicorn/hypercorn).")
  NHUNTS+=("Correlate cookies (sessionid/csrftoken) to distinguish Django vs Flask.")
fi

# generic queries for each hypo
for h in "${HYPOS[@]}"; do
  t="${h#*:}"
  QUERIES+=("$t vulnerability CVE")
done
# preserve whole lines (no word splitting)
mapfile -t QUERIES < <(printf '%s\n' "${QUERIES[@]}" | uniq_lines | head -n 8)
mapfile -t NHUNTS  < <(printf '%s\n' "${NHUNTS[@]}"  | uniq_lines | head -n 8)
mapfile -t RAT     < <(printf '%s\n' "${RAT[@]}"     | uniq_lines | head -n 6)
mapfile -t CVESEED < <(printf '%s\n' "${CVESEED[@]}" | uniq_lines | head -n 8)


# ------------- report (Markdown) -------------
echo "# Web Fingerprinter (curl edition)"
print_kv "Target" "$BASE"
[[ -n "$TITLE" ]] && print_kv "Title" "$TITLE"
[[ -n "${HEADERS[server]:-}" ]] && print_kv "Server" "${HEADERS[server]}"
[[ -n "${HEADERS[content_type]:-}" ]] && print_kv "Content-Type" "${HEADERS[content_type]}"
[[ -n "$FAV_SHA" ]] && print_kv "Favicon (sha1)" "$FAV_SHA"

if [[ "${#COOKIES[@]}" -gt 0 ]]; then
  names=$(printf "%s\n" "${COOKIES[@]}" | sed 's/;.*//' | awk -F= '{print $1}' | paste -sd' ' -)
  echo -e "\n**Cookies (names):** $names"
fi

if [[ "${#ASSETS[@]}" -gt 0 ]]; then
  echo -e "\n**Assets (sample):**"
  for a in "${ASSETS[@]}"; do echo "- $a"; done
fi

if [[ "${#SOURCEMAPS[@]}" -gt 0 ]]; then
  echo -e "\n**Sourcemaps (sample):**"
  for i in "${!SOURCEMAPS[@]}"; do
    echo "- ${SOURCEMAPS[$i]}"
  done
fi

if [[ "${#VERSION_HINTS[@]}" -gt 0 ]]; then
  echo -e "\n**Version hints:** $(printf "%s " "${VERSION_HINTS[@]}")"
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
  if [[ "${#NHUNTS[@]}" -gt 0 ]]; then
    echo -e "\n**Next hunts**"
    for h in "${NHUNTS[@]}"; do echo "- $h"; done
  fi
  if [[ "${#QUERIES[@]}" -gt 0 ]]; then
    echo -e "\n**Search queries**"
    for q in "${QUERIES[@]}"; do echo "- $q"; done
  fi
  if [[ "${#CVESEED[@]}" -gt 0 ]]; then
    echo -e "\n**CVE seeds**"
    for c in "${CVESEED[@]}"; do echo "- $c"; done
  fi
fi

echo
