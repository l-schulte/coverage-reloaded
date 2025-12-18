#!/bin/bash

cd /app/repo

npm install --no-fund

set +e
# npx nyc --reporter=lcov --reporter=text npm test
npx nyc \
    --temp-directory="$COVERAGE_REPORT_PATH/nyc" \
    --reporter=lcov \
    --report-dir="$COVERAGE_REPORT_PATH/lcov" \
    npm test
set -e