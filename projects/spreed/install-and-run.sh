#!/bin/bash
cd /app/repo

npm ci --no-fund

# Choosing to use nyc in both cases (for consistency with "aws-toolkit-vscode").
# In principle, c8 would work in "spreed".
# c8 would need to be installed:  npm install c8 --no-fund
#
# npx c8 --r=lcov -o ../$COVERAGE_REPORT_PATH npm run test:unit
# npx c8 --r=lcov -o ../$COVERAGE_REPORT_PATH npm run test

set +e
if grep -q "test:unit" package.json; then
    echo "Running tests with test:unit script..."

    npx nyc \
        --temp-directory="$COVERAGE_REPORT_PATH/nyc" \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH/lcov" \
        npm run test:unit
else
    echo "Running tests with test script..."
    
    npx nyc \
        --temp-directory="$COVERAGE_REPORT_PATH/nyc" \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH/lcov" \
        npm run test
fi
set -e