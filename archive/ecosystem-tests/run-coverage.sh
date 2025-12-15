#!/bin/bash

starttime=$(date +%s)
echo "=== Starting run-coverage.sh ==="
echo "$(date -d @$timestamp)"
echo "Revision: $revision"
echo "Timestamp: $timestamp"
echo "Package Manager: $package_manager"
echo ""

set -e

cd /app/repo

corepack enable

if [ -n "${package_manager}" ]; then
    corepack prepare "${package_manager}" --activate
fi

pnpm install

set +e
pnpm --filter "./**" test -- --coverage

zip -r "../coverage/$(date -d @$timestamp '+%Y-%m-%d')-$revision.zip" . -i '*/coverage/**' -x '*/node_modules/**'
[ -s "../coverage/$(date -d @$timestamp '+%Y-%m-%d')-$revision.zip" ] || { echo "Error: zip file is empty"; exit 1; }

echo "=== Coverage run completed ==="
endtime=$(date +%s)
elapsed=$((endtime - starttime))
echo "Total time: $elapsed seconds"

