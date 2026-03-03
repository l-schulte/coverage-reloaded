#!/bin/bash

cd /coverage_reloaded/repo

export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
export PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
# Some versions of Puppeteer use this key instead:
export PUPPETEER_CHROME_EXECUTABLE_PATH=/usr/bin/chromium
export CHROMIUM_FLAGS="--no-sandbox --disable-setuid-sandbox"
export PUPPETEER_ARGS='--no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage'

grep -rl "https://github.com" . | xargs sed -i 's|https://github\.com|http://waypack:3000/request/https://github.com|g'

npm install --no-fund

TEST_SCRIPT=$(node -p "require('./package.json').scripts['test']")
TEST_SCRIPT=$(echo "$TEST_SCRIPT" | sed 's/--maxWorkers=[^ ]*/--maxWorkers=2/g')

if echo "$TEST_SCRIPT" | grep -q '\bjest\b'; then
    TEST_SCRIPT=$(echo "$TEST_SCRIPT" | sed 's/\bjest\b/jest --coverage --coverageReporters=lcov/g')
fi

set +e

echo "Executing test script: $TEST_SCRIPT"
PATH="./node_modules/.bin:$PATH" eval "$TEST_SCRIPT"

TEST_EXIT_CODE=$?
set -e

bash ../find-and-move-lcov.sh

if [ "$TEST_EXIT_CODE" -eq 1 ]; then
    echo "WARNING: Tests exited with code $TEST_EXIT_CODE. Coverage may still be collected. Please check test logs for details." >&2
elif [ "$TEST_EXIT_CODE" -gt 1 ]; then
    echo "ERROR: Test runner exited with code $TEST_EXIT_CODE, indicating a possible setup issue" >&2
    exit "$TEST_EXIT_CODE"
fi