#!/usr/bin/env bash
set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh
source /coverage_reloaded/na-if-focus-marker.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    not_applicable "No package.json at this commit"
fi

if [ ! -f gulpfile.js ]; then
    not_applicable "No gulpfile.js at this commit"
fi

na_if_focus_marker --runner mocha --exclude 'test/spec/e2e/**' test

source /coverage_reloaded/resolve-and-pin.sh
resolve_and_pin "bitbucket.org" || true

export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
export PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
export CHROME_BIN=/usr/bin/chromium
export TEST_ALL=true
export NODE_OPTIONS="--max-old-space-size=8096 --max-http-header-size=80000"

# Route transitive phantomjs-prebuilt downloads through WayPack request proxy
export PHANTOMJS_CDNURL="http://waypack:3000/request/https://bitbucket.org/ariya/phantomjs/downloads"
export npm_config_phantomjs_cdnurl="http://waypack:3000/request/https://bitbucket.org/ariya/phantomjs/downloads"

if $IS_NPM_MAIN_PM; then
    npm install --legacy-peer-deps --no-fund --no-audit
elif $IS_YARN_MAIN_PM; then
    yarn install --ignore-engines
elif $IS_PNPM_MAIN_PM; then
    pnpm install
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

# Fix temporal drift in invibesBidAdapter: timestamp 1768600800000 expired on Jan 16, 2026.
# Upstream fixed this dynamically in PR #14355 (commit 84a66a8da0). Replacing with year 2100.
if [ -f test/spec/modules/invibesBidAdapter_spec.js ]; then
    sed -i 's/1768600800000/4102444800000/g' test/spec/modules/invibesBidAdapter_spec.js
fi

# Assert that all chunks completed successfully with >0 tests
assert_suite_ran() {
    local log_file="$1"
    local expected_chunks
    expected_chunks=$(sed -n -E 's/.*Splitting tests into ([0-9]+) chunks.*/\1/p' "$log_file" | head -n 1)

    if [ -n "$expected_chunks" ] && [ "$expected_chunks" -gt 1 ]; then
        local done_chunks zero_summaries positive_summaries
        done_chunks=$(grep -c -E 'Chunk [0-9]+ of [0-9]+: done' "$log_file" || true)
        zero_summaries=$(grep -c -E '✔[[:space:]]+0[[:space:]]+tests completed' "$log_file" || true)
        positive_summaries=$(grep -c -E '✔[[:space:]]+[1-9][0-9]*[[:space:]]+tests completed' "$log_file" || true)

        if [ "$zero_summaries" -gt 0 ]; then
            print_header 2 "ERROR: At least one test chunk reported 0 tests completed"
            print_header 4 "Refusing to record partial coverage from an aborted chunk"
            exit 1
        fi
        if [ "$done_chunks" -ne "$expected_chunks" ]; then
            print_header 2 "ERROR: Expected $expected_chunks chunks but only $done_chunks completed"
            print_header 4 "Refusing to record partial coverage from an incomplete run"
            exit 1
        fi
        if [ "$positive_summaries" -lt "$expected_chunks" ]; then
            print_header 2 "ERROR: Found $positive_summaries successful chunk summaries, expected at least $expected_chunks"
            print_header 4 "Refusing to record partial coverage from an incomplete run"
            exit 1
        fi
    else
        # Monolithic suite (pre-chunking era or 1 chunk)
        if grep -E -q '✔[[:space:]]+0[[:space:]]+tests completed' "$log_file"; then
            print_header 2 "ERROR: Test suite completed 0 tests"
            print_header 4 "Refusing to record partial or empty coverage"
            exit 1
        fi
        if ! grep -E -q '✔[[:space:]]+[1-9][0-9]*[[:space:]]+tests completed' "$log_file"; then
            print_header 2 "ERROR: No successful test summary found in suite output"
            print_header 4 "Refusing to record coverage without executed tests"
            exit 1
        fi
    fi
}

suite_start "unit" "Running unit tests with coverage via gulp test-coverage"
UNIT_LOG=$(mktemp)
set +e
npx gulp test-coverage 2>&1 | tee "$UNIT_LOG"
UNIT_EXIT=${PIPESTATUS[0]}
set -e

assert_suite_ran "$UNIT_LOG"
rm -f "$UNIT_LOG"

bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
suite_end "unit" "$UNIT_EXIT"
