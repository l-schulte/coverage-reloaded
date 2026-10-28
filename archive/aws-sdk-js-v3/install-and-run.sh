#!/usr/bin/env bash
set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/na-if-focus-marker.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    not_applicable "No package.json at this commit"
fi

export AWS_ACCESS_KEY_ID="mock-access-key"
export AWS_SECRET_ACCESS_KEY="mock-secret-key"
export AWS_REGION="us-east-1"
export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=8192"

if [ "$IS_YARN_MAIN_PM" = "true" ]; then
    if [[ "$(yarn --version)" == 1* ]]; then
        yarn config set registry "$WAYPACK_YARN_REGISTRY"
        yarn install --ignore-engines
    else
        yarn config set npmRegistryServer "$WAYPACK_NPM_REGISTRY"
        yarn install --immutable
    fi
elif [ "$IS_NPM_MAIN_PM" = "true" ]; then
    npm config set registry "$WAYPACK_NPM_REGISTRY"
    npm install --no-fund --ignore-scripts
elif [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    pnpm config set registry "$WAYPACK_NPM_REGISTRY"
    pnpm install
else
    print_header 2 "No supported package manager detected"
    exit 1
fi

HAS_BUILD_CRYPTO=$(node -p "!!((require('./package.json').scripts||{})['build:crypto-dependencies'])")
if [ "$HAS_BUILD_CRYPTO" = "true" ]; then
    yarn build:crypto-dependencies
fi

if git show HEAD:turbo.json >/dev/null 2>&1 || git show HEAD:scripts/turbo.js >/dev/null 2>&1; then
    TURBO_FILTERS=("-F=./packages/*")
    [ -d "lib" ] && TURBO_FILTERS+=("-F=./lib/*")
    [ -d "packages-internal" ] && TURBO_FILTERS+=("-F=./packages-internal/*")
    node ./scripts/turbo build "${TURBO_FILTERS[@]}"
elif [ -f node_modules/.bin/lerna ]; then
    ./node_modules/.bin/lerna run build --scope '@aws-sdk/{client-s3,client-sts,client-dynamodb,client-sso,client-cognito-identity,client-polly}' --include-dependencies --no-bail
    ./node_modules/.bin/lerna run build --ignore '@aws-sdk/client-*' --ignore '@aws-sdk/aws-*' --no-bail
fi

if git show HEAD:Makefile >/dev/null 2>&1; then
    if grep -q '^bundles:' Makefile; then
        make bundles
    fi
    if grep -q '^core-prebuild:' Makefile; then
        make core-prebuild
    fi
fi

FOCUS_PATHS=()
if [ -d "packages" ]; then
    FOCUS_PATHS+=("packages")
fi
if [ -d "lib" ]; then
    FOCUS_PATHS+=("lib")
fi
if [ -d "packages-internal" ]; then
    FOCUS_PATHS+=("packages-internal")
fi
if [ -d "tests" ]; then
    FOCUS_PATHS+=("tests")
fi

VITEST_CONFIG=""
if git show HEAD:vitest.config.mts >/dev/null 2>&1; then
    VITEST_CONFIG="vitest.config.mts"
elif git show HEAD:vitest.config.ts >/dev/null 2>&1; then
    VITEST_CONFIG="vitest.config.ts"
fi

if [ -n "$VITEST_CONFIG" ]; then
    na_if_focus_marker --runner vitest "${FOCUS_PATHS[@]}"

    suite_start "unit" "Running unit tests with Vitest"
    set +e
    npx --yes --registry="$VERDACCIO_REGISTRY" c8 --reporter=lcov ./node_modules/.bin/vitest run -c "$VITEST_CONFIG" --maxWorkers=2
    UNIT_EXIT=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
    suite_end "unit" "$UNIT_EXIT"

    VITEST_INTEG_CONFIG=""
    if git show HEAD:vitest.config.integ.mts >/dev/null 2>&1; then
        VITEST_INTEG_CONFIG="vitest.config.integ.mts"
    elif git show HEAD:vitest.config.integ.ts >/dev/null 2>&1; then
        VITEST_INTEG_CONFIG="vitest.config.integ.ts"
    fi

    if [ -n "$VITEST_INTEG_CONFIG" ]; then
        suite_start "integration" "Running integration tests with Vitest"
        set +e
        npx --yes --registry="$VERDACCIO_REGISTRY" c8 --reporter=lcov ./node_modules/.bin/vitest run -c "$VITEST_INTEG_CONFIG" --maxWorkers=2
        INTEG_EXIT=$?
        set -e
        bash /coverage_reloaded/find-and-move-lcov.sh "integration" "false" "$INTEG_EXIT"
        suite_end "integration" "$INTEG_EXIT"
    fi
elif git show HEAD:jest.config.js >/dev/null 2>&1; then
    na_if_focus_marker --runner jest "${FOCUS_PATHS[@]}"

    suite_start "unit" "Running unit tests with Jest"
    set +e
    ./node_modules/.bin/jest --config jest.config.js --coverage --coverageReporters=lcov --runInBand --no-bail
    UNIT_EXIT=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
    suite_end "unit" "$UNIT_EXIT"

    if git show HEAD:jest.config.integ.js >/dev/null 2>&1; then
        suite_start "integration" "Running integration tests with Jest"
        set +e
        ./node_modules/.bin/jest --config jest.config.integ.js --coverage --coverageReporters=lcov --runInBand --no-bail
        INTEG_EXIT=$?
        set -e
        bash /coverage_reloaded/find-and-move-lcov.sh "integration" "false" "$INTEG_EXIT"
        suite_end "integration" "$INTEG_EXIT"
    fi
else
    not_applicable "No known test configuration found"
fi
