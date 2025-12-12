#!/bin/bash

starttime=$(date +%s)
echo "=== Starting run-coverage.sh ==="
echo "$(date -d @$timestamp)"
echo "Revision: $revision"
echo "Timestamp: $timestamp"
echo ""

set -e

cd /app/repo

npm install -g pnpm
pnpm install

set +e
pnpm exec jest --coverage
set -e

zip -r "../coverage/$(date -d @$timestamp '+%Y-%m-%d')-$revision.zip" . -i 'packages/**/coverage/**'
[ -s "../coverage/$(date -d @$timestamp '+%Y-%m-%d')-$revision.zip" ] || { echo "Error: zip file is empty"; exit 1; }

echo "=== Coverage run completed ==="
endtime=$(date +%s)
elapsed=$((endtime - starttime))
echo "Total time: $elapsed seconds"

