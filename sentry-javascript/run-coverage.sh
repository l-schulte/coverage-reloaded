#!/bin/bash

echo "=== Starting run-coverage.sh ==="
echo "$(date -d @$timestamp)"
echo "Revision: $revision"
echo "Timestamp: $timestamp"
echo ""

cd /app/repo

yarn install
yarn build

npx lerna run test -- --coverage

zip -r ../coverage/$(date -d @"$timestamp")-"$revision".zip . -i '**/coverage/**' -i '**/packages/**/coverage/**'

echo "=== Coverage run completed ==="
endtime=$(date +%s)
elapsed=$((endtime - starttime))
echo "Total time: $elapsed seconds"

