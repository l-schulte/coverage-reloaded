#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

print_header 2 "Installing dependencies"

# --force: many commits pair @vue/cli-plugin-unit-jest@4.x with @vue/cli-service@5.x,
# which is a peer-dep mismatch (npm 8+ ERESOLVE). --legacy-peer-deps skips installing
# the required peer dep (v4 service), causing runtime failures. --force installs the
# whole tree, resolving both versions, which matches npm 7's legacy behavior.
npm install --no-fund --ignore-engine --force

npm install -g nyc --no-fund

# ── Run tests with coverage ─────────────────────────────────────────────────────

set +e

TEST_UNIT_SCRIPT=$(node -p "require('./package.json').scripts['test:unit'] || ''")
TEST_SCRIPT=$(node -p "require('./package.json').scripts.test || ''")
TEST_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:coverage'] || ''")

NUM_RUNNER_RAN=0

if echo "$TEST_UNIT_SCRIPT $TEST_SCRIPT $TEST_COVERAGE_SCRIPT" | grep -q "vitest"; then
    NUM_RUNNER_RAN=$((NUM_RUNNER_RAN + 1))
    print_header 2 "Running vitest tests with coverage"
    npx vitest run --coverage --coverage.reporter=lcov --coverage.reportOnFailure=true --bail=0
    TEST_EXIT=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "vitest" "false" "$TEST_EXIT"
fi
if echo "$TEST_UNIT_SCRIPT $TEST_SCRIPT $TEST_COVERAGE_SCRIPT" | grep -q "jest"; then
    NUM_RUNNER_RAN=$((NUM_RUNNER_RAN + 1))
    print_header 2 "Running jest tests with coverage"
    npx jest --coverage --coverageReporters=lcov --no-cache --bail=false
    TEST_EXIT=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "jest" "false" "$TEST_EXIT"
fi
if echo "$TEST_UNIT_SCRIPT $TEST_SCRIPT $TEST_COVERAGE_SCRIPT" | grep -q "vue-cli-service"; then
    NUM_RUNNER_RAN=$((NUM_RUNNER_RAN + 1))
    print_header 2 "Running vue-cli-service tests with coverage"
    npx vue-cli-service test:unit --coverage --coverageReporters lcov --no-cache --bail=false
    TEST_EXIT=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "vue-cli-service" "false" "$TEST_EXIT"
fi

if [ "$NUM_RUNNER_RAN" -eq 0 ]; then
    print_header 2 "ERROR" "Unknown test infrastructure, cannot inject coverage flags"
    exit 1
fi

set -e

print_header 1 "spreed coverage run complete"

