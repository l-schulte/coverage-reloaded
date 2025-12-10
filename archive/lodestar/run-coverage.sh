#!/bin/bash

starttime=$(date +%s)
echo "=== Starting run-coverage.sh ==="
echo "$(date -d @$timestamp)"
echo "Revision: $revision"
echo "Timestamp: $timestamp"
echo ""

set -e

cd /app/repo

yarn install
yarn build

# npx playwright install
# npx lerna exec --concurrency 1 -- vitest run --coverage.enabled=true --coverage.include="src/**/*.ts" \
#     --project unit \
#     --project browser \
#     --project e2e 

npx lerna run test --no-bail -- --coverage --coverage.enabled=true --coverage.include="src/**/*.ts"

zip -r "../coverage/$(date -d @$timestamp '+%Y-%m-%d')-$revision.zip" . -i 'packages/**/coverage/**'
[ -s "../coverage/$(date -d @$timestamp '+%Y-%m-%d')-$revision.zip" ] || { echo "Error: zip file is empty"; exit 1; }

echo "=== Coverage run completed ==="
endtime=$(date +%s)
elapsed=$((endtime - starttime))
echo "Total time: $elapsed seconds"

