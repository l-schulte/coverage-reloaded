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

# Jest-puppeteer preset runs component code inside a browser process, which
# Jest's coverage collector cannot instrument. Only the lib/* test helpers get
# measured, so coverage is meaningless. Flag such commits as not_applicable.
JEST_PRESET=$(node -p "const j = require('./package.json').jest || {}; j.preset || ''" 2>/dev/null || echo "")
if [ "$JEST_PRESET" = "jest-puppeteer" ]; then
    print_header 2 "NOT APPLICABLE: jest-puppeteer preset detected — tests run in a browser, coverage not collectable"
    exit 2
fi

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
TEST_SCRIPT=$(echo "$TEST_SCRIPT" | sed 's/--maxWorkers=[^ ]*//g; s/--maxWorkers [0-9]*//g')
TEST_SCRIPT="$TEST_SCRIPT --coverage --coverageReporters=lcov --maxWorkers=2"

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