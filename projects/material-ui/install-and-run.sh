#!/bin/bash

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

set -e

cd /coverage_reloaded/repo

# The test scripts/listChangedFiles.test.js calls git rev-parse to determine
# the merge-base. Because CIRCLECI=true is exported below, listChangedFiles
# prepends 'origin/' to the branch name ('origin/next').
# Populate both the local branch and remote-tracking ref for 'next' at HEAD
# so listChangedFiles succeeds cleanly without network access.
git branch -f next HEAD
git update-ref refs/remotes/origin/next HEAD

if $IS_NPM_MAIN_PM; then
    print_header 2 "Installing dependencies with npm..."
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-fund --include=dev

    COMMAND="npm run"
elif $IS_YARN_MAIN_PM; then
    # Requires a non-existing dependency (vitest-mui, was deleted from registry)
    # Workaround: providing the file (vitest-mui-0.3.3.tgz and vitest-mui-0.3.4.tgz) in the waypack machine
    # Integrity checks fail for this file.
    # Workaround: clean cache with yarn cache clean disable integrity checks for yarn installs by adding --update-checksums
    print_header 2 "Installing dependencies with yarn..."

    # if yarn is legacy
    if [[ "$(yarn --version)" == 1* ]]; then
        print_header 4 "Yarn v1 detected"
        yarn cache clean --force
        yarn install --update-checksums --ignore-engines
    else
        print_header 4 "Yarn v2+ detected"
        yarn cache clean
        yarn install
    fi

    COMMAND="yarn run"
elif $IS_PNPM_MAIN_PM; then
    print_header 2 "Installing dependencies with pnpm..."
    pnpm install

    COMMAND="pnpm run"
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

# The test @material-ui/codemod v4.0.0 optimal-imports expects no console.warn() calls,
# but browserslist emits a warning if caniuse-lite is outdated. Update it to silence the warning.
# This goes through waypack so subsequent commits reuse the cached version.
npx --registry=$WAYPACK_NPM_REGISTRY browserslist@latest --update-db 2>/dev/null || true

TEST_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:coverage'] || ''")
TEST_UNIT_SCRIPT=$(node -p "require('./package.json').scripts['test:unit'] || ''")

NODE_MAJOR=$(node -e "console.log(process.version.substring(1).split('.')[0])" 2>/dev/null || true)

# Force CI mode so the project's vitest config picks the lcovonly coverage reporter.
export CI=true

# Force CIRCLECI so the project's .mocharc.js raises the mocha timeout to 5000ms
# (its "Circle CI has low-performance CPUs" branch) instead of the 2000ms local
# default, which our instrumented, cold-cache container trips on.
export CIRCLECI=true

prepare_mocha_node_options() {
    # Prevent Node.js from reparsing ambiguous .js files as ESM (which breaks __dirname usage)
    # Only needed on Node >=20 where --experimental-detect-module is default.
    # Must be set via NODE_OPTIONS (not just .mocharc.js) because nyc wraps mocha and
    # nyc needs to receive the flag before it spawns mocha.
    if [ "${NODE_MAJOR:-0}" -ge 20 ] 2>/dev/null; then
        print_header 4 "Node.js version is >=20, setting NODE_OPTIONS"
        export NODE_OPTIONS="$NODE_OPTIONS --no-experimental-detect-module"
    fi
}

run_mocha_coverage() {
    # Run $COMMAND test:coverage (nyc wrapping mocha). nyc persists raw coverage in
    # .nyc_output; the follow-up nyc report renders it to lcov. If mocha aborted
    # mid-run the collected data is partial, so discard it and keep a non-zero code.
    set +e
    set -o pipefail
    OUTPUT=$($COMMAND test:coverage 2>&1 | tee /dev/stderr)
    EXIT_CODE=${PIPESTATUS[0]}
    set -e

    if echo "$OUTPUT" | grep -q 'Exception during run:'; then
        print_header 4 "ERROR: Mocha aborted mid-run (Exception during run:) — coverage is partial, not generating lcov"
        rm -rf .nyc_output
        EXIT_CODE=1
    else
        npx --registry=$WAYPACK_REGISTRY_CURRENT nyc report --reporter=lcov
    fi
}

# Determine the coverage runner from what test:coverage actually invokes at this commit:
#   * nx run nx_test_coverage  -> nx/nyc/mocha era (2024-05 .. 2025-12)
#   * nyc ... mocha            -> direct nyc/mocha era (before 2024-05)
#   * (test:unit -> vitest)    -> vitest + v8 coverage era (after 2025-12)
if [[ "$TEST_COVERAGE_SCRIPT" == *"nx_test_coverage"* ]]; then
    print_header 2 "Nx-based coverage detected (nx run nx_test_coverage)"

    # nyc wraps mocha and does not inherit mocha's require config, so nyc needs its own
    # babel registration to load .ts/.tsx files. Use the project's setupBabel which
    # configures babel-register with TS extensions. Patch only the nx_test_coverage script.
    if jq -e '.scripts.nx_test_coverage | type == "string"' package.json > /dev/null; then
        print_header 4 "Patching nx_test_coverage to require @mui/internal-test-utils/setupBabel"
        jq '.scripts.nx_test_coverage |= gsub("nyc "; "nyc --require @mui/internal-test-utils/setupBabel ")' package.json > package.json.tmp
        mv package.json.tmp package.json
    fi

    suite_start "test_coverage" "Running tests with coverage (nx/nyc/mocha)"
    prepare_mocha_node_options
    run_mocha_coverage
    bash /coverage_reloaded/find-and-move-lcov.sh "test_coverage" "false" "$EXIT_CODE"
    suite_end "test_coverage" "$EXIT_CODE"
elif [[ "$TEST_COVERAGE_SCRIPT" == *"mocha"* ]]; then
    print_header 2 "Direct nyc/mocha coverage detected"

    suite_start "test_coverage" "Running tests with coverage (nyc/mocha)"
    prepare_mocha_node_options
    run_mocha_coverage
    bash /coverage_reloaded/find-and-move-lcov.sh "test_coverage" "false" "$EXIT_CODE"
    suite_end "test_coverage" "$EXIT_CODE"
elif [[ "$TEST_UNIT_SCRIPT" == *"vitest"* ]] || [[ "$TEST_COVERAGE_SCRIPT" == *"vitest"* ]]; then
    print_header 2 "Vitest coverage detected"

    # Prevent vitest from attempting to launch browser tests via playwright (no browser binaries in container)
    export TEST_SCOPE=node

    suite_start "test_coverage" "Running tests with coverage (vitest)"
    set +e
    set -o pipefail
    OUTPUT=$($COMMAND test:coverage 2>&1 | tee /dev/stderr)
    EXIT_CODE=${PIPESTATUS[0]}
    set -e
    # vitest (v8 coverage provider) writes coverage/lcov.info itself; no nyc report needed.
    bash /coverage_reloaded/find-and-move-lcov.sh "test_coverage" "false" "$EXIT_CODE"
    suite_end "test_coverage" "$EXIT_CODE"
else
    print_header 2 "Unknown test:coverage script: >$TEST_COVERAGE_SCRIPT< (test:unit: >$TEST_UNIT_SCRIPT<). Skipping coverage collection."
    exit 1
fi
