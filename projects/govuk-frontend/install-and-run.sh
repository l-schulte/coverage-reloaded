#!/bin/bash

# TODO: Pass exit code as 3rd arg to find-and-move-lcov.sh
#       TEST_EXIT_CODE is captured below but not forwarded.
#       Change: bash ../find-and-move-lcov.sh "unit" "false" "$TEST_EXIT_CODE"

set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
export PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
# Some versions of Puppeteer use this key instead:
export PUPPETEER_CHROME_EXECUTABLE_PATH=/usr/bin/chromium
export CHROMIUM_FLAGS="--no-sandbox --disable-setuid-sandbox"
export PUPPETEER_ARGS='--no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage'

# Replace GitHub URLs in source files so tests route through WayPack cache.
# Exclude package.json files — they contain repository.url which is read at
# build time (e.g. govuk-prototype-kit validate-plugin) and must remain valid
# public GitHub URLs.
grep -rl "https://github.com" . | grep -v "package.json" | xargs -r sed -i 's|https://github\.com|http://waypack:3000/request/https://github.com|g'

print_header 2 "Installing dependencies"
npm install --no-fund

PRETEST_SCRIPT=$(node -p "const s = require('./package.json').scripts; (s && s.pretest) || ''" 2>/dev/null || echo "")
if [ -n "$PRETEST_SCRIPT" ]; then
    print_header 2 "Running pretest script"
    npm run pretest
fi

TEST_SCRIPT=$(node -p "require('./package.json').scripts['test']")
TEST_SCRIPT=$(echo "$TEST_SCRIPT" | sed 's/--maxWorkers=[^ ]*/--maxWorkers=2/g')

if echo "$TEST_SCRIPT" | grep -q '\bjest\b'; then
    TEST_SCRIPT=$(echo "$TEST_SCRIPT" | sed 's/\bjest\b/jest --coverage --coverageReporters=lcov/g')
fi

print_header 2 "Running tests with coverage"
suite_start "test" "Running tests with coverage"

set +e

echo "Executing test script: $TEST_SCRIPT"
PATH="./node_modules/.bin:$PATH" eval "$TEST_SCRIPT"

TEST_EXIT_CODE=$?
set -e

bash ../find-and-move-lcov.sh "test" "false" "$TEST_EXIT_CODE"
suite_end "test" "$TEST_EXIT_CODE"

if [ "$TEST_EXIT_CODE" -eq 1 ]; then
    echo "WARNING: Tests exited with code $TEST_EXIT_CODE. Coverage may still be collected. Please check test logs for details." >&2
elif [ "$TEST_EXIT_CODE" -gt 1 ]; then
    echo "ERROR: Test runner exited with code $TEST_EXIT_CODE, indicating a possible setup issue" >&2
    exit "$TEST_EXIT_CODE"
fi