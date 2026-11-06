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

# Backport upstream commit df6cda5e2 (PR #13464): eliminate real-time wait in dgkeywordRtdProvider_spec.js.
# An orphaned setTimeout(..., 1000) scheduled request.respond() after done(), colliding asynchronously with
# the shared Sinon fake XHR server of subsequent tests and aborting Mocha runs in Karma (~50-60% coverage).
if [ -f test/spec/modules/dgkeywordRtdProvider_spec.js ] && grep -q "setTimeout(() => {" test/spec/modules/dgkeywordRtdProvider_spec.js; then
    python3 -c "
import re
path = 'test/spec/modules/dgkeywordRtdProvider_spec.js'
with open(path) as f:
    c = f.read()
if 'sinon.useFakeTimers()' not in c:
    c = re.sub(
        r\"(it\('should get profiles timeout\.', function \([^\)]*\) \{)\",
        r\"\1\n      const clock = sinon.useFakeTimers();\",
        c
    )
    c = re.sub(
        r\"setTimeout\(\(\) => \{[\s\S]*?\}, 1000\);?\",
        \"\"\"const request = server.requests[0];
      if (request) {
        clock.tick(50);
        if (request) {
          request.respond(
            200,
            DUMMY_RESPONSE_HEADER,
            JSON.stringify(DUMMY_RESPONSE)
          );
        }
      }
      clock.restore();\"\"\",
        c
    )
    with open(path, 'w') as f:
        f.write(c)
"
fi

# Backport upstream commit e953c2f91 (PR #13234) for chunking introduction window (May 28 - June 3, 2025):
# Force single-pass testCoverage before multi-chunk coverage merging was added upstream in PR #13483
if [ -f gulpfile.js ] && \
   grep -q "karmaRunner.js" gulpfile.js && \
   grep -q "NODE_OPTIONS: '--max-old-space-size=8096'" gulpfile.js && \
   ! grep -q "TEST_CHUNKS:" gulpfile.js && \
   ! grep -q "mergeCoverage" gulpfile.js; then
    sed -i "s/NODE_OPTIONS: '--max-old-space-size=8096'/NODE_OPTIONS: '--max-old-space-size=8096', TEST_CHUNKS: '1'/g" gulpfile.js
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
