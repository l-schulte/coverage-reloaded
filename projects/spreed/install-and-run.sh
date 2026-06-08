#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

print_header 2 "Installing dependencies"

npm ci --no-fund

npm install -g nyc --no-fund

# ── Detect test infrastructure era ─────────────────────────────────────────────

print_header 2 "Detecting test infrastructure era"

TEST_SCRIPT=$(node -p "require('./package.json').scripts.test || ''")
TEST_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:coverage'] || ''")

echo "test script:       $TEST_SCRIPT"
echo "test:coverage:     $TEST_COVERAGE_SCRIPT"

set +e

# ── Run tests with coverage ─────────────────────────────────────────────────────

if [ -n "$TEST_COVERAGE_SCRIPT" ]; then
    print_header 2 "Running tests with test:coverage script"

    if echo "$TEST_COVERAGE_SCRIPT" | grep -q "vitest"; then
        npm run test:coverage -- --coverage.reporter=lcov --coverage.reportOnFailure=true
    elif echo "$TEST_COVERAGE_SCRIPT" | grep -q "jest"; then
        npm run test:coverage -- --coverageReporters=lcov
    else
        npm run test:coverage
    fi
elif echo "$TEST_SCRIPT" | grep -q "vitest"; then
    print_header 2 "Injecting coverage flags for vitest"
    npx vitest run --coverage --coverage.reporter=lcov --coverage.reportOnFailure=true
elif echo "$TEST_SCRIPT" | grep -q "jest"; then
    print_header 2 "Injecting coverage flags for jest"
    npx jest --coverage --coverageReporters=lcov
elif echo "$TEST_SCRIPT" | grep -q "Error: no test specified"; then
    print_header 2 "Skipping tests" "No test infrastructure configured"
else
    print_header 2 "Running tests" "unknown test runner — passing flags directly"
    npm run test -- --coverage.enabled=true --coverage.reporter=lcov
fi

set -e

print_header 2 "Collecting coverage reports"
bash ../find-and-move-lcov.sh

