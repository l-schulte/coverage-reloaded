#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

# ── Dependency installation ───────────────────────────────────────────────────

print_header 2 "Installing dependencies"

# Some yarn.lock entries have resolved URLs pointing to a now-defunct internal
# nexus registry (nexus.stackline.com). Rewrite them to the WayPack npm registry
# so yarn can fetch them through the local cache/proxy.
if $IS_YARN_MAIN_PM; then
    print_header 3 "Patching nexus.stackline.com URLs in yarn.lock → WayPack"
    sed -i "s|https://nexus.stackline.com/repository/npm-group/|${WAYPACK_NPM_REGISTRY}|g" yarn.lock
    yarn install --frozen-lockfile 2>&1 || yarn install 2>&1
    PM_RUN="yarn run"
elif $IS_NPM_MAIN_PM; then
    npm ci 2>&1 || npm install 2>&1
    PM_RUN="npm run"
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

# ── Install global build deps ─────────────────────────────────────────────────

print_header 2 "Installing global build dependencies"

# cross-env is used by many packages' prepare scripts (e.g. babel-plugin-remove-graphql-queries)
# but may not be hoisted to the root node_modules. Install it globally so it's on PATH.
npm install -g cross-env 2>&1

# ── Bootstrap (lerna prepare) ─────────────────────────────────────────────────

print_header 2 "Bootstrapping packages (lerna prepare)"

# Gatsby is a lerna monorepo. Each package needs its build step (babel, tsc, etc.)
# before tests can run. The bootstrap script handles this via lerna run prepare.
# We run it directly rather than via the npm script to avoid lint steps.

npx lerna run prepare 2>&1 || {
    echo "WARNING: lerna run prepare failed — some packages may not be built"
}

# Integration tests spawn gatsby.js directly (not via `node`), so it needs
# the executable bit. Babel's build output inherits the source file's mode
# (644), which lacks +x. Fix it here so spawn() doesn't get EACCES.
chmod +x packages/gatsby/dist/bin/gatsby.js 2>/dev/null || true

# ── Detect test infrastructure era ─────────────────────────────────────────────

print_header 2 "Detecting test infrastructure era"

TEST_SCRIPT=$(node -p "require('./package.json').scripts.test || ''")
TEST_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:coverage'] || ''")
TEST_INTEGRATION_SCRIPT=$(node -p "require('./package.json').scripts['test:integration'] || ''")

echo "test:               $TEST_SCRIPT"
echo "test:coverage:      $TEST_COVERAGE_SCRIPT"
echo "test:integration:   $TEST_INTEGRATION_SCRIPT"

# ── Test runner era analysis from command_changes.csv ─────────────────────────
#
# Gatsby uses Jest as its sole test runner across its entire history.
# The test infrastructure has been remarkably stable:
#
# Era 1 (1577915773 — 1652259478):  jest (root:.: jest)
#   - test script:  npm-run-all -s lint jest test:peril
#   - test:coverage: jest --coverage
#   - test:integration: jest --config=integration-tests/jest.config.js
#   - test:peril: cd peril && yarn test
#
# Era 2 (1652259479 — present):     jest (root:.: jest)
#   - test script:  npm-run-all --npm-path npm -s lint jest test:peril
#   - (same test:coverage and test:integration as Era 1)
#   - Only change: --npm-path npm added to npm-run-all invocation
#
# Key characteristics:
#   - Test runner: jest (always)
#   - Coverage tool: jest --coverage (built-in, always)
#   - Monorepo: lerna + yarn workspaces (packages/*)
#   - Integration tests: separate jest config at integration-tests/jest.config.js
#   - Peril tests: separate package at peril/ with its own jest config
#   - No nyc, c8, vitest, mocha, or karma ever used

# ── Run tests with coverage ────────────────────────────────────────────────────

print_header 2 "Running unit tests with jest --coverage"

set +e

# Run the main test suite with coverage
# We use jest --coverage directly (same as test:coverage script) to avoid
# running lint and peril which are not needed for coverage collection.
# Explicitly request lcov reporter — jest's default includes lcov, but
# we can't assume every commit's jest config hasn't overridden it.
# Use the repo-local jest binary (node_modules/.bin/jest) rather than npx,
# because npx installs jest in an isolated cache where it can't resolve
# modules like 'glob' that the project's jest.config.js requires.
# --maxWorkers=1: serial execution prevents PID exhaustion and port conflicts
# from multiple gatsby build/develop processes running concurrently.
./node_modules/.bin/jest --coverage --coverageReporters=lcov --maxWorkers=1 2>&1
JEST_EXIT=$?

set -e

if [ $JEST_EXIT -ne 0 ]; then
    echo "WARNING: jest tests exited with code $JEST_EXIT — coverage data preserved but may be partial"
fi

print_header 2 "Collecting unit test coverage reports"
bash /coverage_reloaded/find-and-move-lcov.sh "unit"

# ── Integration tests ─────────────────────────────────────────────────────────

print_header 2 "Running integration tests with jest --coverage"

if [ -f integration-tests/jest.config.js ]; then
    set +e

    # --forceExit: integration tests spawn gatsby build/develop processes that
    # aren't always cleaned up, causing jest to hang after the test run.
    ./node_modules/.bin/jest --config=integration-tests/jest.config.js --coverage --coverageReporters=lcov --maxWorkers=1 --forceExit 2>&1
    INTEGRATION_EXIT=$?

    set -e

    if [ $INTEGRATION_EXIT -ne 0 ]; then
        echo "WARNING: integration tests exited with code $INTEGRATION_EXIT — coverage data preserved but may be partial"
    fi

    print_header 2 "Collecting integration test coverage reports"
    bash /coverage_reloaded/find-and-move-lcov.sh "integration"
else
    echo "NOTICE: integration-tests/jest.config.js not found at this commit — skipping integration tests"
fi
