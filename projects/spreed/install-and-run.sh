#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

print_header 2 "Installing dependencies"

npm install --legacy-peer-deps --no-fund

set +e
if node -p "require('./node_modules/vue/package.json').version" > /dev/null 2>&1; then
    VUE_VERSION=$(node -p "require('./node_modules/vue/package.json').version")
    if [ ! -d "node_modules/vue-template-compiler" ]; then
        npm install --no-save --legacy-peer-deps vue-template-compiler@"$VUE_VERSION"
    fi
fi
set -e

npm install -g nyc --no-fund

# ── Run tests with coverage ─────────────────────────────────────────────────────

set +e

TEST_UNIT_SCRIPT=$(node -p "require('./package.json').scripts['test:unit'] || ''")
TEST_SCRIPT=$(node -p "require('./package.json').scripts.test || ''")
TEST_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:coverage'] || ''")

if echo "$TEST_UNIT_SCRIPT $TEST_SCRIPT $TEST_COVERAGE_SCRIPT" | grep -q "vitest"; then
    print_header 2 "Running vitest tests with coverage"
    npx vitest run --coverage --coverage.reporter=lcov --coverage.reportOnFailure=true --bail=0
elif echo "$TEST_UNIT_SCRIPT $TEST_SCRIPT $TEST_COVERAGE_SCRIPT" | grep -q "jest"; then
    print_header 2 "Running jest tests with coverage"
    npx jest --coverage --coverageReporters=lcov --no-cache --bail=false
elif echo "$TEST_UNIT_SCRIPT $TEST_SCRIPT $TEST_COVERAGE_SCRIPT" | grep -q "vue-cli-service"; then
    print_header 2 "Running vue-cli-service tests with coverage"
    npx vue-cli-service test:unit --coverage --coverageReporters lcov --no-cache --bail=false
else
    print_header 2 "ERROR" "Unknown test infrastructure, cannot inject coverage flags"
    exit 1
fi

TEST_EXIT=$?
set -e

print_header 2 "Collecting coverage reports"
bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"

print_header 1 "spreed coverage run complete"

