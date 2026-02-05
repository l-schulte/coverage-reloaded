#!/bin/bash

cd /coverage_reloaded/repo

npm install --no-fund

set +e

npx --registry=$WAYPACK_NPM_REGISTRY nyc \
    --reporter=lcov \
    --report-dir="$COVERAGE_REPORT_PATH" \
    npm test
    
set -e