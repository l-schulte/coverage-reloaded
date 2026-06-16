#!/bin/bash

set -e

set -euo pipefail

. /coverage_reloaded/logging.sh
cd /coverage_reloaded/repo

# ── Patch yarn.lock ───────────────────────────────────────────
print_header 2 "Patching yarn.lock" "replacing stale/renamed registry entries"

sed -i 's|hugomrdias/concat-stream|max-mapper/concat-stream|g' yarn.lock
sed -i 's|BitGo/blake2b-wasm|mafintosh/blake2b-wasm|g' yarn.lock
sed -i 's|193cdb71656c1a6c7f89b05d0327bb9b758d071b|refs/tags/v2.0.0|g' yarn.lock
sed -i 's|BitGo/blake2b|BitGo/BitGoJS|g' yarn.lock

# ── Install dependencies ──────────────────────────────────────
print_header 2 "Installing dependencies"

export NODE_ENV=development
export YARN_CHECKSUM_BEHAVIOR=ignore

yarn install

# ── Detect test infrastructure era ───────────────────────────
print_header 2 "Detecting test infrastructure era" "reading scripts from package.json"

TEST_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:coverage'] || ''")
TEST_COVERAGE_JEST_SCRIPT=$(node -p "require('./package.json').scripts['test:coverage:jest'] || ''")
TEST_UNIT_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:unit:coverage'] || ''")
TEST_UNIT_WEBPACK_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:unit:webpack:coverage'] || ''")
TEST_INTEGRATION_SCRIPT=$(node -p "require('./package.json').scripts['test:integration'] || ''")
TEST_INTEGRATION_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:integration:coverage'] || ''")

# E2E tests are run through selenium and do not expose coverage data.

set +e

# ── Unit coverage ─────────────────────────────────────────────
print_header 1 "Unit Coverage Collection"

if [ -n "$TEST_COVERAGE_JEST_SCRIPT" ]; then
    print_header 3 "Era: test:coverage:jest (jest+nyc)" "$TEST_COVERAGE_JEST_SCRIPT"
    if [[ "$TEST_COVERAGE_JEST_SCRIPT" == *"./test/run-unit-tests.js"* ]]; then
        print_header 3 "Strategy: run-unit-tests.js → nyc lcov report"
        yarn test:coverage:jest
        npx nyc report \
            --reporter=lcov \
            --temp-dir ./coverage \
            --report-dir ./coverage/lcov \
            --include-all-sources false
    elif [[ "$TEST_COVERAGE_JEST_SCRIPT" == "yarn test:unit:jest --coverage --maxWorkers=2 && yarn jest-it-up -m 5" ]]; then
        print_header 3 "Strategy: test:unit:jest --coverage (bypass jest-it-up threshold check)"
        yarn test:unit:jest --coverage --maxWorkers=2 --coverageReporters=lcov --no-bail
    else
        print_header 3 "Strategy: test:coverage:jest --coverageReporters=lcov"
        yarn test:coverage:jest --coverageReporters=lcov --no-bail
    fi
elif [ -n "$TEST_UNIT_COVERAGE_SCRIPT" ]; then
    print_header 3 "Era: test:unit:coverage (jest)" "$TEST_UNIT_COVERAGE_SCRIPT"
    yarn run test:unit:coverage --coverageReporters=lcov --no-bail
elif [ -n "$TEST_COVERAGE_SCRIPT" ]; then
    print_header 3 "Era: test:coverage (nyc)" "$TEST_COVERAGE_SCRIPT"
    LCOV_SCRIPT="${TEST_COVERAGE_SCRIPT//--reporter=text/--reporter=lcov}"
    print_header 3 "Substituted --reporter=text" "$TEST_COVERAGE_SCRIPT"
    eval "npx $LCOV_SCRIPT"
else
    print_header 3 "Era: unknown — no coverage script found"
    echo "No coverage test script found... raising error." >&2
    exit 1
fi

print_header 3 "Collecting unit lcov output"
bash ../find-and-move-lcov.sh unit "false" "$TEST_EXIT_CODE"

# ── Integration coverage ──────────────────────────────────────
print_header 1 "Integration Coverage Collection"

if [ -n "$TEST_INTEGRATION_COVERAGE_SCRIPT" ]; then
    print_header 3 "Strategy: test:integration:coverage --coverageReporters=lcov"
    yarn run test:integration:coverage --coverageReporters=lcov --no-bail
elif [ -n "$TEST_INTEGRATION_SCRIPT" ]; then
    print_header 3 "Strategy: test:integration (no dedicated coverage script)"
else
    print_header 3 "No integration test script found — skipping"
fi

print_header 3 "Collecting integration lcov output"
bash ../find-and-move-lcov.sh integration "false" "$TEST_EXIT_CODE"

set -e