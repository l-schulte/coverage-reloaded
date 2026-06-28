#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

print_header 2 "Installing dependencies"

if $IS_NPM_MAIN_PM; then
    npm install --no-fund --legacy-peer-deps
else
    print_header 2 "Expected npm as package manager, got: $package_manager"
    exit 1
fi

print_header 2 "Detecting test scripts and infrastructure"

HAS_WORKSPACES=$(node -p "typeof require('./package.json').workspaces !== 'undefined'")

print_header 4 "workspaces: $HAS_WORKSPACES"

# Problem: @serverlessinc/sf-core is closed source and a required dependency in certain eras
# Solution: Skip those commits, since they cannot be tested without access to the private package. 
HAS_CLOSED_SOURCE_DEPENDENCY=$(node -p "typeof require('./package.json').dependencies['@serverlessinc/sf-core'] !== 'undefined'")
if [ "$HAS_CLOSED_SOURCE_DEPENDENCY" = "true" ]; then
    print_header 2 "NOT APPLICABLE: This commit depends on @serverlessinc/sf-core, which is closed source and cannot be tested in this environment."
    exit 2
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
    print_header 2 "Running tests with coverage (nyc + mocha)"

    # The coverage script is always "nyc npm test" throughout this era.
    # Run it directly rather than relying on the script name.
    # Mocha does not bail by default, so no --no-bail needed.
    set +e
    npx --registry=$VERDACCIO_REGISTRY nyc --reporter=lcov npm test
    TEST_EXIT=$?
    set -e

    print_header 2 "Collecting coverage reports"
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"

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

    # Worspace names:
    # mcp -> @serverless/mcp: test:unit, test
    # serverless -> @serverless/framework: test:unit, test
    # sf-core -> @serverlessinc/sf-core: test:unit, test
    # engine -> @serverless/engine: test, test:integration

    print_header 3 "Running mcp + serverless + sf-core command 'test:unit'"
    set +e
    npm run test:unit \
        -w @serverless/mcp \
        -w @serverless/framework \
        -w @serverlessinc/sf-core \
        -- --coverage --coverage-reporters=lcov --runInBand
    TEST_EXIT=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "true" "$TEST_EXIT"

    print_header 3 "Running engine + mcp + sf-core command 'test'"

    set +e
    npm run test \
        -w @serverless/engine \
        -w @serverless/mcp \
        -w @serverlessinc/sf-core \
        -- --coverage --coverage-reporters=lcov --runInBand
    TEST_EXIT=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "test" "true" "$TEST_EXIT"

    print_header 3 "Running engine command 'test:integration'"

    set +e
    npm run test:integration \
        -w @serverless/engine \
        -- --coverage --coverage-reporters=lcov --runInBand
    TEST_EXIT=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "integration" "true" "$TEST_EXIT"
fi