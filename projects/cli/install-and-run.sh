#!/bin/bash

cd /app/repo

npm install --no-fund

set +e
# npx nyc --reporter=lcov --reporter=text npm test
npx nyc \
    --reporter=lcov \
    --report-dir="$COVERAGE_REPORT_PATH" \
    npm test
set -e