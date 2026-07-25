#!/bin/bash

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

set -e

cd /coverage_reloaded/repo

# The test scripts/listChangedFiles.test.js calls git rev-parse next to determine
# the merge-base, but we checkout commits in detached HEAD with no branches.
# Create a local 'next' branch pointing at HEAD so the test doesn't crash.
git branch next HEAD 2>/dev/null || true

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

TEST_SCRIPT=$(node -p "require('./package.json').scripts['test'] || ''")
TEST_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:coverage'] || ''")

if [ -n "$TEST_COVERAGE_SCRIPT" ]; then
    suite_start "test_coverage" "Running tests with coverage"

    set +e

    # Prevent Node.js from reparsing ambiguous .js files as ESM (which breaks __dirname usage)
    # Only needed on Node >=20 where --experimental-detect-module is default
    # Must be set via NODE_OPTIONS (not just .mocharc.js) because nyc wraps mocha and
    # nyc needs to receive the flag before it spawns mocha.
    if [ "$(node -e "console.log(process.version.substring(1).split('.')[0])")" -ge 20 ] 2>/dev/null; then
        print_header 4 "Node.js version is >=20, setting NODE_OPTIONS"
        export NODE_OPTIONS="$NODE_OPTIONS --no-experimental-detect-module"
    fi

    HAS_COVERAGE_SCRIPT=$(jq -r '.scripts["test:coverage"] // empty' package.json)
    if [ -z "$HAS_COVERAGE_SCRIPT" ]; then
        print_header 2 "NOT APPLICABLE: No test:coverage script found in package.json. Skipping coverage collection."
        exit 2
    fi

    # Patch nyc command to include @babel/register for TypeScript support.
    # nyc wraps mocha and doesn't inherit mocha's require config, so nyc needs
    # its own babel registration to load .ts/.tsx files.
    # Use the project's setupBabel which configures babel-register with TS extensions.
    jq '.scripts.nx_test_coverage |= gsub("nyc "; "nyc --require @mui/internal-test-utils/setupBabel ")' package.json > package.json.tmp
    mv package.json.tmp package.json

    set -o pipefail
    OUTPUT=$($COMMAND test:coverage 2>&1 | tee /dev/stderr)
    EXIT_CODE=${PIPESTATUS[0]}
    set -e

    if echo "$OUTPUT" | grep -q 'Exception during run:'; then
        print_header 4 "ERROR: Mocha aborted mid-run (Exception during run:) — coverage is partial, not generating lcov"
        rm -rf .nyc_output
        EXIT_CODE=1
    else
        npx --registry=$VERDACCIO_REGISTRY nyc report --reporter=lcov
    fi

    bash /coverage_reloaded/find-and-move-lcov.sh "test_coverage" "false" "$EXIT_CODE"
    suite_end "test_coverage" "$EXIT_CODE"
elif [[ "$TEST_SCRIPT" == *"jest"* ]]; then
    suite_start "jest" "Running tests with jest enabled"
    set +e
    $COMMAND test --coverage --coverageReporters=lcov
    EXIT_CODE=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "jest" "true" "$EXIT_CODE"
    suite_end "jest" "$EXIT_CODE"
else
    print_header 2 "Unknown test scripts: >$TEST_SCRIPT<; test:coverage: >$TEST_COVERAGE_SCRIPT<. Skipping coverage collection."
    exit 1
fi