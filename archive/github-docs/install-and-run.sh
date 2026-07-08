#!/bin/bash

source /coverage_reloaded/logging.sh

set -e

cd /coverage_reloaded/repo

print_header 2 "Installing dependencies"

# Try installing without --legacy-peer-deps
if npm install --no-fund; then
    print_header 4 "Installation succeeded without --legacy-peer-deps"
else
    print_header 4 "Peer dependency conflicts detected. Retrying with --legacy-peer-deps..."
    npm install --no-fund --legacy-peer-deps
    # Deduplicate to resolve version conflicts
    # npm dedupe
fi

print_header 2 "Building"

npm run build

print_header 2 "Running tests"

TEST_SCRIPT=$(node -p "require('./package.json').scripts['test']")

set +e

if [[ "$TEST_SCRIPT" == *"jest"* ]]; then
    suite_start "jest" "Running tests with Jest"
    NODE_OPTIONS=--experimental-vm-modules npx jest --coverage --passWithNoTests
    EXIT_CODE=$?
    set -e
    bash ../find-and-move-lcov.sh "jest" "false" "$EXIT_CODE"
    suite_end "jest" "$EXIT_CODE"
    
elif [[ "$TEST_SCRIPT" == *"vitest"* ]]; then
    suite_start "vitest" "Running tests with Vitest"
    # Problem: dependency issues with vitest cause coverage to fail
    # Solution: install latest vitest and coverage plugin
    npm install vitest@latest @vitest/coverage-v8@latest
    npx vitest \
        --passWithNoTests \
        --coverage \
        --coverage.reporter=lcov \
        --coverage.reportOnFailure=true
    EXIT_CODE=$?
    set -e
    bash ../find-and-move-lcov.sh "vitest" "false" "$EXIT_CODE"
    suite_end "vitest" "$EXIT_CODE"
fi