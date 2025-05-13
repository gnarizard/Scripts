#!/usr/bin/env bash
URL="$1"
WORDLIST="$2"

# sanity check
if [[ -z "$URL" || -z "$WORDLIST" ]]; then
  echo "Usage: $0 <base-url> <userlist>"
  exit 1
fi

export URL
export PARALLEL_READ_TIMEOUT=0
parallel --jobs 30 --bar '
  code=$(curl -s -o /dev/null -w "%{http_code}" "${URL}/{}")
  if [[ $code -eq 200 ]]; then
    echo "[+] {} exists"
  fi
' :::: "$WORDLIST"
