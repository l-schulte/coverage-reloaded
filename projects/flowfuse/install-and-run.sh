#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

print_header 2 "Installing dependencies"

if $IS_YARN_MAIN_PM; then
    yarn install --frozen-lockfile
    PM_RUN="yarn run"
elif $IS_NPM_MAIN_PM; then
    npm install
    PM_RUN="npm run"
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

print_header 2 "Detecting test scripts and infrastructure"

TEST_SCRIPT=$(node -p "p=require('./package.json').scripts; (p.test || '')")
TEST_UNIT_SCRIPT=$(node -p "p=require('./package.json').scripts; (p['test:unit'] || '')")
TEST_UNIT_FORGE_SCRIPT=$(node -p "p=require('./package.json').scripts; (p['test:unit:forge'] || '')")
TEST_UNIT_FRONTEND_SCRIPT=$(node -p "p=require('./package.json').scripts; (p['test:unit:frontend'] || '')")
TEST_SYSTEM_SCRIPT=$(node -p "p=require('./package.json').scripts; (p['test:system'] || '')")

HAS_NYC=0
if [ -f .nycrc.json ] || node -e "process.exit(require('./package.json').devDependencies?.nyc ? 0 : 1)" 2>/dev/null; then
    HAS_NYC=1
fi

HAS_FORGE=0
if [ -n "$TEST_UNIT_FORGE_SCRIPT" ]; then
    HAS_FORGE=1
fi

HAS_FRONTEND=0
if [ -n "$TEST_UNIT_FRONTEND_SCRIPT" ]; then
    HAS_FRONTEND=1
fi

HAS_UNIT=0
if [ -n "$TEST_UNIT_SCRIPT" ]; then
    HAS_UNIT=1
fi

HAS_SYSTEM=0
if [ -n "$TEST_SYSTEM_SCRIPT" ]; then
    HAS_SYSTEM=1
fi

HAS_TEST=0
if [ -n "$TEST_SCRIPT" ] && ! echo "$TEST_SCRIPT" | grep -q "Error: no test specified"; then
    HAS_TEST=1
fi

print_header 4 "test:                 $TEST_SCRIPT"
print_header 4 "test:unit:            $TEST_UNIT_SCRIPT"
print_header 4 "test:unit:forge:      $TEST_UNIT_FORGE_SCRIPT"
print_header 4 "test:unit:frontend:   $TEST_UNIT_FRONTEND_SCRIPT"
print_header 4 "test:system:          $TEST_SYSTEM_SCRIPT"
print_header 4 "HAS_NYC=$HAS_NYC  HAS_FORGE=$HAS_FORGE  HAS_FRONTEND=$HAS_FRONTEND  HAS_UNIT=$HAS_UNIT  HAS_SYSTEM=$HAS_SYSTEM  HAS_TEST=$HAS_TEST"

if [ $HAS_FORGE -eq 0 ] && [ $HAS_FRONTEND -eq 0 ] && [ $HAS_UNIT -eq 0 ] && [ $HAS_SYSTEM -eq 0 ] && [ $HAS_TEST -eq 0 ]; then
    print_header 2 "NOT APPLICABLE" "No test scripts found at this commit, no test infrastructure to run"
    exit 2
fi

if [ $HAS_NYC -eq 1 ]; then
    COVER_TOOL=(npx --registry="$VERDACCIO_REGISTRY" nyc --reporter=lcov)
    print_header 4 "Coverage tool: nyc"
else
    COVER_TOOL=(npx --registry="$VERDACCIO_REGISTRY" c8 --reporter=lcov --)
    print_header 4 "Coverage tool: c8"
fi

# Forge backend tests start the app server and need frontend/dist/index.html.
print_header 2 "Building frontend assets"
npm run build

print_header 2 "Running tests with coverage"

# IMPORTANT: set +e around test execution so failures don't abort the script.
# Coverage collection (find-and-move-lcov.sh) runs with set -e and must fail loudly.

# --- test:unit:forge (mocha/nyc or mocha/c8) ---
if [ $HAS_FORGE -eq 1 ]; then
    print_header 3 "Running test:unit:forge"
    set +e
    "${COVER_TOOL[@]}" npm run test:unit:forge -- --exit
    FORGE_EXIT=$?
    set -e

    print_header 2 "Collecting forge unit coverage reports"
    bash /coverage_reloaded/find-and-move-lcov.sh "forge-unit" "false" "$FORGE_EXIT"
else
    print_header 4 "NOTICE: No test:unit:forge script found — skipping forge unit tests"
fi

# --- test:unit:frontend (vitest) ---
if [ $HAS_FRONTEND -eq 1 ]; then
    print_header 3 "Running test:unit:frontend (vitest)"

    # Coverage provider c8 is missing for some commits — check if it exists in the registry first.
    C8_VERSION=$(npm view @vitest/coverage-c8 version 2>/dev/null || true)
    if [ -n "$C8_VERSION" ]; then
        print_header 4 "Installing @vitest/coverage-c8..."
        npm install --no-save --legacy-peer-deps @vitest/coverage-c8
    fi

    set +e
    npx --registry=$WAYPACK_NPM_REGISTRY vitest run --config ./config/vitest.config.ts \
        --coverage.enabled --coverage.reporter=lcov --reporter=verbose
    FRONTEND_EXIT=$?
    set -e

    print_header 2 "Collecting frontend coverage reports"
    bash /coverage_reloaded/find-and-move-lcov.sh "frontend-unit" "false" "$FRONTEND_EXIT"
else
    print_header 4 "NOTICE: No test:unit:frontend script found — skipping frontend tests"
fi

# --- test:unit (mocha/nyc or mocha/c8) — only if forge and frontend are absent ---
if [ $HAS_UNIT -eq 1 ]; then
    if [ $HAS_FORGE -eq 1 ] || [ $HAS_FRONTEND -eq 1 ]; then
        print_header 4 "NOTICE: test:unit skipped because test:unit:forge or test:unit:frontend already covers unit tests"
    else
        print_header 3 "Running test:unit"
        set +e
        "${COVER_TOOL[@]}" npm run test:unit -- --exit
        UNIT_EXIT=$?
        set -e

        print_header 2 "Collecting unit test coverage reports"
        bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
    fi
else
    print_header 4 "NOTICE: No test:unit script found — skipping unit tests"
fi

# --- test:system (mocha/nyc or mocha/c8) ---
if [ $HAS_SYSTEM -eq 1 ]; then
    print_header 3 "Running test:system"
    set +e
    "${COVER_TOOL[@]}" npm run test:system -- --exit
    SYSTEM_EXIT=$?
    set -e

    print_header 2 "Collecting system test coverage reports"
    bash /coverage_reloaded/find-and-move-lcov.sh "system" "false" "$SYSTEM_EXIT"
else
    print_header 4 "NOTICE: No test:system script found — skipping system tests"
fi

# --- test fallback — only when no per-suite scripts exist ---
if [ $HAS_FORGE -eq 0 ] && [ $HAS_FRONTEND -eq 0 ] && [ $HAS_UNIT -eq 0 ] && [ $HAS_SYSTEM -eq 0 ] && [ $HAS_TEST -eq 1 ]; then
    print_header 3 "No per-suite scripts found — falling back to c8 on test script"

    print_header 4 "Installing c8 locally for fallback..."
    npm install --no-save c8@7

    set +e
    npx --registry=$VERDACCIO_REGISTRY c8 --reporter=lcov -- npm run test
    TEST_EXIT=$?
    set -e

    print_header 2 "Collecting coverage reports"
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"
fi

print_header 1 "FlowFuse coverage run complete"
