#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

print_header 2 "Detecting test infrastructure"

HAS_VITEST=$(node -p "Object.keys(require('./package.json').devDependencies || {}).includes('vitest')")
HAS_JEST=$(node -p "Object.keys(require('./package.json').devDependencies || {}).includes('jest')")

if [ "$HAS_VITEST" = "false" ] && [ "$HAS_JEST" = "false" ]; then
    print_header 2 "NOT APPLICABLE" "Neither vitest nor jest in devDependencies at this commit"
    exit 2
fi

print_header 2 "Installing dependencies"

if $IS_YARN_MAIN_PM; then
    yarn install --ignore-engines
elif $IS_NPM_MAIN_PM; then
    npm install --no-audit --no-fund
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

# ── Runner dispatch ─────────────────────────────────────────────
# History (from command_changes.csv):
#   Jan 2020 – Feb 2025  jest   (yarn).  ESM needs NODE_OPTIONS=--experimental-vm-modules
#                                   from Jul 2021 (project's own `jest` script).
#   Feb 2025 – Mar 2025  vitest (yarn)
#   Mar 2025 – present   vitest (npm)
#
# Branch on what the checked-out commit contains, never on dates.

if [ "$HAS_VITEST" = "true" ]; then
    print_header 3 "vitest era detected"

    if $IS_YARN_MAIN_PM; then
        VITEST="yarn run vitest"
    else
        VITEST="npx --registry=$WAYPACK_NPM_REGISTRY vitest"
    fi

    # ── Unit suite (test/) ──────────────────────────────────────
    suite_start "unit" "vitest unit tests (test/) with coverage"
    set +e
    $VITEST run test/ --coverage --coverage.reporter=lcov --coverage.reportOnFailure=true --minWorkers=1 --maxWorkers=1
    TEST_EXIT=$?
    set -e
    bash ../find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"
    suite_end "unit" "$TEST_EXIT"

    # ── Examples suite (examples/) ──────────────────────────────
    suite_start "examples" "vitest example spec tests (examples/) with coverage"
    set +e
    $VITEST run examples/ --coverage --coverage.reporter=lcov --coverage.reportOnFailure=true --minWorkers=1 --maxWorkers=1
    TEST_EXIT=$?
    set -e
    bash ../find-and-move-lcov.sh "examples" "false" "$TEST_EXIT"
    suite_end "examples" "$TEST_EXIT"

    print_header 3 "Runtime suite (test-runtime/, browser via @vitest/browser-playwright) SKIPPED — browser-based visual/selection tests, not behavioral coverage"

else
    print_header 3 "jest era detected"

    # The 2020 – Feb 2021 jest config used `preset: jest-puppeteer`,
    # which launches a browser even for pure unit tests.  The unit tests
    # in test/ never touch page/browser globals, so generate an override
    # config that drops the preset and runs them in node.
    JEST_CONFIG_ARG=""
    PRESET=$(node -p "(require('./package.json').jest || {}).preset || ''" 2>/dev/null || echo "")
    if echo "$PRESET" | grep -q "puppeteer"; then
        print_header 4 "jest-puppeteer preset found — generating node-env override config"
        node -e "
            const fs = require('fs');
            const j = require('./package.json').jest;
            delete j.preset;
            j.testEnvironment = 'node';
            fs.writeFileSync('./vl-jest-config.json', JSON.stringify(j));
        "
        JEST_CONFIG_ARG="--config ./vl-jest-config.json"
    fi

    # ESM era (Jul 2021 – Feb 2025): jest needs --experimental-vm-modules;
    # the project's own `jest` script carried it.  Replicate here so the
    # direct jest invocation below works the same way.
    JEST_SCRIPT=$(node -p "(require('./package.json').scripts || {}).jest || ''" 2>/dev/null || echo "")
    if echo "$JEST_SCRIPT" | grep -q "experimental-vm-modules"; then
        print_header 4 "ESM jest era — setting NODE_OPTIONS=--experimental-vm-modules"
        export NODE_OPTIONS="--experimental-vm-modules"
    fi

    JEST="npx --registry=$WAYPACK_NPM_REGISTRY jest"

    # ── Unit suite (test/) ──────────────────────────────────────
    suite_start "unit" "jest unit tests (test/) with coverage"
    set +e
    # shellcheck disable=SC2086
    $JEST $JEST_CONFIG_ARG --collectCoverage test/ --coverageReporters=lcov --maxWorkers=1 --forceExit
    TEST_EXIT=$?
    set -e
    bash ../find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"
    suite_end "unit" "$TEST_EXIT"

    # ── Examples suite (examples/) ──────────────────────────────
    suite_start "examples" "jest example spec tests (examples/) with coverage"
    set +e
    # shellcheck disable=SC2086
    $JEST $JEST_CONFIG_ARG --collectCoverage examples/ --coverageReporters=lcov --maxWorkers=1 --forceExit
    TEST_EXIT=$?
    set -e
    bash ../find-and-move-lcov.sh "examples" "false" "$TEST_EXIT"
    suite_end "examples" "$TEST_EXIT"

    print_header 3 "Runtime suite (test-runtime/, jest + puppeteer) SKIPPED — browser-based visual/selection tests, not behavioral coverage"
fi

print_header 1 "Vega-Lite coverage run complete"
