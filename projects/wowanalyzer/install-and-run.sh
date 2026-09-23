#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

# jest_check_executed  (also covers vitest)
# Streams a jest/react-app-rewired OR vitest run's output through live (still reaches the
# log) and checks for a "Tests" summary. Returns 0 if the run completed (even with failing
# tests) and 1 if it did NOT (transform-load crash, config error, worker death, …). On an
# incomplete run it deletes any partial lcov.info so find-and-move-lcov.sh fails hard
# instead of emitting misleading partial coverage. Mirrors flowfuse's mocha_check_passing.
jest_check_executed() {
    local out_file; out_file=$(mktemp)
    tee "$out_file"
    # vitest/jest colourise the "Tests"/"Test Files" summary labels even when
    # stdout is a pipe, so the raw stream carries ANSI SGR codes before the
    # label and the anchored grep below never matches. strip-ansi-cli@3.0.0 is
    # pinned because it supports every Node major this project runs (12-24).
    if ! npx -y --registry="$VERDACCIO_REGISTRY" strip-ansi-cli@3.0.0 < "$out_file" \
            | grep -qE '^[[:space:]]*(Tests|Test Files)[: ]'; then
        echo "  [NFO] test run did not complete (no Tests: summary) — discarding partial coverage and failing hard"
        find "$REPOPATH" -name lcov.info -not -path '*/node_modules/*' -delete
        rm -f "$out_file"; return 1
    fi
    rm -f "$out_file"; return 0
}

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    not_applicable "No package.json at this commit, no test infrastructure to run"
fi

print_header 2 "Detecting test infrastructure"

# Detect test runner from package.json scripts
TEST_SCRIPT=$(node -p "require('./package.json').scripts.test || ''")

print_header 2 "Installing dependencies"

if $IS_YARN_MAIN_PM; then
    yarn cache clean
    # --ignore-engines: skip Node.js engine compatibility checks so that
    # packages like @playwright/test (requires Node >=16) don't block the
    # install when the project's Dockerfile specifies an older Node version.
    yarn install --ignore-engines
elif $IS_PNPM_MAIN_PM; then
    pnpm install
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

# Install vitest coverage provider if needed (not included in project deps)
if echo "$TEST_SCRIPT" | grep -q "vitest"; then
    print_header 3 "Installing @vitest/coverage-v8"
    if $IS_YARN_MAIN_PM; then
        yarn add --dev @vitest/coverage-v8
    elif $IS_PNPM_MAIN_PM; then
        VITEST_VERSION="$(node -p "require('vitest/package.json').version")"
        if [ -f pnpm-workspace.yaml ]; then
            pnpm add -D -w "@vitest/coverage-v8@$VITEST_VERSION"
        else
            pnpm add -D "@vitest/coverage-v8@$VITEST_VERSION"
        fi
    fi
fi

# Note: The project also defines test:interface, test:parser, and test:integration
# sub-suite scripts, but these are just filtered views of the main `test` script
# (e.g. "yarn test --exclude src/parser" or "yarn test ./src/parser"). The main
# `test` suite already covers all behavioral code paths in a single pass, so
# running sub-suites separately would only produce overlapping lcov files with
# no new coverage data.

set +e

if echo "$TEST_SCRIPT" | grep -q "vitest"; then
    suite_start "vitest" "Running tests with coverage"
    print_header 3 "Running tests (vitest)"
    npx --registry="$WAYPACK_NPM_REGISTRY" vitest run --coverage --coverage.reporter=lcov --coverage.reportOnFailure=true 2>&1 | jest_check_executed
    TEST_EXIT=${PIPESTATUS[0]}
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "vitest" "false" "$TEST_EXIT"
    suite_end "vitest" "$TEST_EXIT"
elif echo "$TEST_SCRIPT" | grep -q "react-app-rewired"; then
    suite_start "react-app-rewired" "Running tests with coverage"
    print_header 3 "Running tests (react-app-rewired / jest)"
    npx --registry="$WAYPACK_NPM_REGISTRY" react-app-rewired test --runInBand --coverage --coverageReporters=lcov --watchAll=false 2>&1 | jest_check_executed
    TEST_EXIT=${PIPESTATUS[0]}
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "react-app-rewired" "false" "$TEST_EXIT"
    suite_end "react-app-rewired" "$TEST_EXIT"
else
    print_header 3 "Test runner not configured."
    TEST_EXIT=2
fi

print_header 1 "WoWAnalyzer coverage run complete"
