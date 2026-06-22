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
    npx --registry=$WAYPACK_NPM_REGISTRY nyc --reporter=lcov npm test
    TEST_EXIT=$?
    set -e

    print_header 2 "Collecting coverage reports"
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"

# ──────────────────────────────────────────────
# Era 2: Workspace monorepo with jest
# ──────────────────────────────────────────────
elif [ "$HAS_WORKSPACES" = "true" ]; then
    print_header 2 "Running tests with coverage (jest --coverage)"

    # The root test script runs: npm run test:unit -w @serverlessinc/sf-core -w @serverless/framework
    # These invoke jest with --experimental-vm-modules.
    # No coverage tooling is present natively — use jest's built-in --coverage.
    # Use --runInBand to avoid parallelism issues.

    print_header 3 "Running sf-core + serverless unit tests"
    set +e
    npm run test:unit -w @serverlessinc/sf-core -w @serverless/framework -- --coverage --coverage-reporters=lcov --runInBand
    TEST_EXIT=$?
    set -e

    print_header 2 "Collecting coverage reports"
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "true" "$TEST_EXIT"

    # Also run engine tests if they exist
    if node -e "process.exit(require('fs').existsSync('packages/engine/package.json') ? 0 : 1)" 2>/dev/null; then
        HAS_ENGINE_TEST=$(node -p "!!(require('./packages/engine/package.json').scripts || {}).test")
        if [ "$HAS_ENGINE_TEST" = "true" ]; then
            print_header 3 "Running engine tests"
            set +e
            npm run test -w packages/engine -- --coverage --coverage-reporters=lcov --runInBand
            ENGINE_EXIT=$?
            set -e

            print_header 2 "Collecting engine coverage reports"
            bash /coverage_reloaded/find-and-move-lcov.sh "engine" "true" "$ENGINE_EXIT"
        fi
    fi

    # Run MCP tests if they exist
    if node -e "process.exit(require('fs').existsSync('packages/mcp/package.json') ? 0 : 1)" 2>/dev/null; then
        HAS_MCP_TEST=$(node -p "!!(require('./packages/mcp/package.json').scripts || {}).test")
        if [ "$HAS_MCP_TEST" = "true" ]; then
            print_header 3 "Running MCP tests"
            set +e
            npm run test -w packages/mcp -- --coverage --coverage-reporters=lcov --runInBand
            MCP_EXIT=$?
            set -e

            print_header 2 "Collecting MCP coverage reports"
            bash /coverage_reloaded/find-and-move-lcov.sh "mcp" "true" "$MCP_EXIT"
        fi
    fi
fi