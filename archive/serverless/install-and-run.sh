#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

# ──────────────────────────────────────────────────────────
# Pre-install checks — must run BEFORE npm install
# ──────────────────────────────────────────────────────────

# Problem: @serverlessinc/sf-core is closed source and a required dependency in certain eras.
# Solution: Skip those commits, since they cannot be tested without access to the private package.
# This must run before npm install to avoid a noisy E404 from the registry.
HAS_CLOSED_SOURCE_DEPENDENCY=$(node -p "Object.keys(require('./package.json').dependencies || {}).includes('@serverlessinc/sf-core')")
if [ "$HAS_CLOSED_SOURCE_DEPENDENCY" = "true" ]; then
    not_applicable "This commit depends on @serverlessinc/sf-core, which is closed source and cannot be tested in this environment."
fi

HAS_WORKSPACES=$(node -p "typeof require('./package.json').workspaces !== 'undefined'")
print_header 4 "workspaces: $HAS_WORKSPACES"

# ──────────────────────────────────────────────────────────
# Install dependencies
# ──────────────────────────────────────────────────────────
print_header 2 "Installing dependencies"

# Allow pre-release versions for @serverless companion packages (v3 cluster era)
node /coverage_reloaded/allow-prerelease-deps.js

if $IS_NPM_MAIN_PM; then
    npm install --no-fund --legacy-peer-deps
else
    print_header 2 "Expected npm as package manager, got: $package_manager"
    exit 1
fi

# NOTE: Both eras have integration/e2e test suites that deploy real AWS
# infrastructure (CloudFormation stacks, Lambda functions, S3 buckets, etc.).
# These require valid AWS credentials and network access to AWS APIs, neither
# of which is available inside the container. Only behavioral (unit) test
# suites are run here.

# ──────────────────────────────────────────────
# Era 1: Single-package repo with nyc + mocha
# ──────────────────────────────────────────────
if [ "$HAS_WORKSPACES" = "false" ]; then
    suite_start "mocha" "Running tests with coverage (nyc + mocha)"

    # The coverage script is always "nyc npm test" throughout this era.
    # Run it directly rather than relying on the script name.
    # Mocha does not bail by default, so no --no-bail needed.
    # FORCE_COLOR=1: tests assert colored subprocess output (e.g. chalk's
    # dim "---" separators in invoke/invokeLocal tests). Without a TTY chalk
    # strips ANSI codes and the assertions fail (~32 commits in the 2021 era).
    #
    # mocha-multi is NOT used — it hacks process.exit and breaks on Node 16+.
    # Instead, capture mocha's spec output and parse "N passing" to count tests.
    #
    # script -qec "...": allocates a controlling PTY. The Ruby invokeLocal
    # wrapper (runtimeWrappers/invoke.rb attach_tty) reopens /dev/tty onto
    # $stdin; without a controlling terminal this raises ENXIO and the rescue
    # prints "tty unavailable", polluting the handler JSON and failing the 3
    # invokeLocalRuby tests in EVERY run. With a PTY the reopen succeeds and
    # nothing is printed. -e propagates the child exit code; -q suppresses
    # "Script started/finished" chatter; /dev/null discards the timing file.

    test_output=$(mktemp)

    set +e
    FORCE_COLOR=1 script -qec \
        "npx --registry=$WAYPACK_REGISTRY_CURRENT nyc --reporter=lcov npm test" \
        /dev/null 2>&1 | tee "$test_output"
    TEST_EXIT=${PIPESTATUS[0]}
    set -e

    echo "  [DIAG] test exit code: $TEST_EXIT"
    echo "  [DIAG] node version: $(node -v)"
    echo "  [DIAG] mocha version: $(node -p "require('./node_modules/mocha/package.json').version" 2>/dev/null || echo 'not installed')"
    echo "  [DIAG] nyc version: $(node -p "require('./node_modules/nyc/package.json').version" 2>/dev/null || echo 'not installed')"

    # Parse test count from mocha spec output: "  2909 passing (3m)"
    n_tests=$(grep -oP '\d+(?= passing)' "$test_output" | tail -1)
    rm -f "$test_output"

    if [ -z "$n_tests" ]; then
        n_tests=0
    fi

    echo "  [DIAG] parsed test count from stdout: $n_tests"

    if [ "$n_tests" = "0" ]; then
        echo "Mocha behaved unexpectedly: 0 tests parsed from stdout, exit code $TEST_EXIT."
        exit 1
    fi

    bash /coverage_reloaded/find-and-move-lcov.sh "mocha" "false" "$TEST_EXIT"
    suite_end "mocha" "$TEST_EXIT"

# ──────────────────────────────────────────────
# Era 2: Workspace monorepo with jest
# ──────────────────────────────────────────────
elif [ "$HAS_WORKSPACES" = "true" ]; then
    print_header 2 "Running tests with coverage (jest --coverage)"

    # Less than 20 commits actually fall into this era.

    # The root test script runs: npm run test:unit -w @serverlessinc/sf-core -w @serverless/framework
    # These invoke jest with --experimental-vm-modules.
    # No coverage tooling is present natively — use jest's built-in --coverage.
    # Use --runInBand to avoid parallelism issues.

    # Workspace names:
    # mcp -> @serverless/mcp: test:unit, test (test includes e2e)
    # serverless -> @serverless/framework: test:unit
    # sf-core -> @serverlessinc/sf-core: test:unit, test, test:resolvers
    # engine -> @serverless/engine: test, test:integration

    suite_start "unit-workspace" "Running mcp + serverless + sf-core command 'test:unit'"
    set +e
    script -qec "npm run test:unit -w @serverless/mcp -w @serverless/framework -w @serverlessinc/sf-core -- --coverage --coverage-reporters=lcov --runInBand --json --outputFile=.test_results.json" /dev/null
    TEST_EXIT=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "true" "$TEST_EXIT"
    suite_end "unit-workspace" "$TEST_EXIT"

    suite_start "resolvers-workspace" "Running sf-core command 'test:resolvers'"
    set +e
    script -qec "npm run test:resolvers -w @serverlessinc/sf-core -- --coverage --coverage-reporters=lcov --runInBand --json --outputFile=.test_results.json" /dev/null
    TEST_EXIT=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "resolvers" "true" "$TEST_EXIT"
    suite_end "resolvers-workspace" "$TEST_EXIT"

    suite_start "test-workspace" "Running engine + mcp + sf-core command 'test'"
    set +e
    script -qec "npm run test -w @serverless/engine -w @serverless/mcp -w @serverlessinc/sf-core -- --coverage --coverage-reporters=lcov --runInBand --json --outputFile=.test_results.json" /dev/null
    TEST_EXIT=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "test" "true" "$TEST_EXIT"
    suite_end "test-workspace" "$TEST_EXIT"

    suite_start "integration-workspace" "Running engine command 'test:integration'"
    set +e
    script -qec "npm run test:integration -w @serverless/engine -- --coverage --coverage-reporters=lcov --runInBand --json --outputFile=.test_results.json" /dev/null
    TEST_EXIT=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "integration" "true" "$TEST_EXIT"
    suite_end "integration-workspace" "$TEST_EXIT"
fi