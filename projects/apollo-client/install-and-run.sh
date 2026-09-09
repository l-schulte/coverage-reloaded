#!/usr/bin/env bash
set -euo pipefail

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

cd /coverage_reloaded/repo
REPO_ROOT="$(pwd)"
COVERAGE_DIR="$REPO_ROOT/coverage"

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit"
    exit 2
fi

ROOT_COVERAGE=$(node -p "((require('./package.json').scripts||{}).coverage) || ''" || true)
ROOT_TEST=$(node -p "((require('./package.json').scripts||{}).test) || ''" || true)
if [ -z "$ROOT_COVERAGE" ] && [ -z "$ROOT_TEST" ]; then
    print_header 2 "NOT APPLICABLE" "No coverage or test script at this commit"
    exit 2
fi

print_header 4 "Root coverage script: $ROOT_COVERAGE"
print_header 4 "Root test script: $ROOT_TEST"

print_header 2 "Installing dependencies"

if [ "$IS_NPM_MAIN_PM" = "true" ]; then
    npm install --legacy-peer-deps
    PM_RUN="npm run"
elif [ "$IS_YARN_MAIN_PM" = "true" ]; then
    yarn install --frozen-lockfile
    PM_RUN="yarn"
elif [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    pnpm install --frozen-lockfile
    PM_RUN="pnpm run"
else
    print_header 2 "Unsupported package manager: $package_manager"
    exit 1
fi

print_header 2 "Building workspace packages"

HAS_BUILD=$(node -p "!!((require('./package.json').scripts||{}).build)")
if [ "$HAS_BUILD" = "true" ]; then
    $PM_RUN build
else
    print_header 2 "No root build script at this commit — skipping build"
fi

print_header 2 "Patching package.json test scripts to collect coverage"
node /coverage_reloaded/patch-coverage.js

print_header 2 "Running unit tests with coverage"

HAS_COVERAGE_SCRIPT=$(node -p "!!((require('./package.json').scripts||{}).coverage)")
HAS_TEST_SCRIPT=$(node -p "!!((require('./package.json').scripts||{}).test)")

if [ "$HAS_COVERAGE_SCRIPT" = "true" ]; then
    suite_start "unit" "Running coverage script (env -u CI $PM_RUN coverage -- --maxWorkers=2)"

    set +e
    env -u CI $PM_RUN coverage -- --maxWorkers=2
    UNIT_EXIT=$?
    set -e

    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
    suite_end "unit" "$UNIT_EXIT"
elif [ "$HAS_TEST_SCRIPT" = "true" ]; then
    suite_start "unit" "Running test script (env -u CI $PM_RUN test -- --maxWorkers=2)"

    set +e
    env -u CI $PM_RUN test -- --maxWorkers=2
    UNIT_EXIT=$?
    set -e

    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
    suite_end "unit" "$UNIT_EXIT"
else
    print_header 2 "No test script found — skipping unit tests"
fi

print_header 2 "Integration tests: SKIPPED"

print_header 4 "integration-tests/ workspace = Playwright e2e (off-limits, not worth effort)"
print_header 4 "scripts/memory (test:memory) & integration-tests/node = node:test smoke (no src coverage)"
print_header 4 "Behavioral integration surface already covered by the Jest unit run over src/__tests__"

print_header 1 "apollo-client coverage run complete"
