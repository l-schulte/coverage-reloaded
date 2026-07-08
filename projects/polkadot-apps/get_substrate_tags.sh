#!/usr/bin/env bash
set -euo pipefail

OUT="substrate_tags.tsv"
> "$OUT"

URL="https://hub.docker.com/v2/namespaces/parity/repositories/substrate/tags?page_size=100"

while [ "$URL" != "null" ] && [ -n "$URL" ]; do
  RESPONSE=$(curl -s "$URL")
  echo "$RESPONSE" | jq -r '.results[] | "\(.name)\t\(.tag_last_pushed)\t\(.digest)"' >> "$OUT"
  URL=$(echo "$RESPONSE" | jq -r '.next')
  sleep 0.3   # be polite to the API
done

echo "Done. $(wc -l < "$OUT") tags written to $OUT"