#!/bin/bash

# TODO: Add set +e + capture exit code + pass as 3rd arg to find-and-move-lcov.sh for each variant
#       Issues:
#       - No set +e at all — tests run under set -e, so a failure aborts the script
#       - No exit code captured per variant
#       - No warning/error handling for exit codes 0/1 vs >1
#       Fix per variant: set +e / <test> / EXIT_CODE=$? / set -e / warning handling / bash ../find-and-move-lcov.sh <variant> "false" "$EXIT_CODE"

set -e

cd /coverage_reloaded/repo

npm install --no-fund

# if transpile or pretest commands exist, run them before the test command
for cmd in transpile pretest; do
    if npm run | grep -q "$cmd"; then
        npm run "$cmd"
    fi
done

# Extract the layered test script
TEST_SCRIPT=$(node -p "require('./package.json').scripts['test:node']")


# Identify which of these exist: ./config/.mocharc.js or ./config/.mocharc.cjs
if [ -f "./config/.mocharc.js" ]; then
    echo "Using Mocha config: .mocharc.js"
    MOCHA_CONFIG="./config/.mocharc.js"
elif [ -f "./config/.mocharc.cjs" ]; then
    echo "Using Mocha config: .mocharc.cjs"
    MOCHA_CONFIG="./config/.mocharc.cjs"
else
    echo "No Mocha config found. Exiting."
    exit 1
fi


echo "Execuiting with npx registry set to $WAYPACK_NPM_REGISTRY"
echo "Mocha config file: $MOCHA_CONFIG"

npm install @babel/register --no-fund
npm install source-map-support --no-fund

if [[ "$TEST_SCRIPT" == *"mocha"* ]]; then
    echo "Running tests with mocha enabled"
    npx --registry=$VERDACCIO_REGISTRY c8 \
        --require source-map-support/register \
        --require @babel/register \
        --reporter=lcov \
        mocha \
            --no-bail \
            --expose-gc \
            --config "$MOCHA_CONFIG" \
            ./test_tmp/unit.test.js

    bash ../find-and-move-lcov.sh mocha
fi
if [[ "$TEST_SCRIPT" == *"test:node:lokijs"* ]]; then
    echo "Running tests with lokijs enabled"
    DEFAULT_STORAGE=lokijs \
    npx --registry=$VERDACCIO_REGISTRY c8 \
        --require source-map-support/register \
        --require @babel/register \
        --reporter=lcov \
        mocha \
            --no-bail \
            --expose-gc \
            --config "$MOCHA_CONFIG" \
            ./test_tmp/unit.test.js

    bash ../find-and-move-lcov.sh lokijs
fi
if [[ "$TEST_SCRIPT" == *"test:node:pouchdb"* ]]; then
    echo "Running tests with pouchdb enabled"
    DEFAULT_STORAGE=pouchdb \
    npx --registry=$VERDACCIO_REGISTRY c8 \
        --require source-map-support/register \
        --require @babel/register \
        --reporter=lcov \
        mocha \
            --no-bail \
            --expose-gc \
            --config "$MOCHA_CONFIG" \
            ./test_tmp/unit.test.js

    bash ../find-and-move-lcov.sh pouchdb
fi
if [[ "$TEST_SCRIPT" == *"test:node:dexie"* ]]; then
    echo "Running tests with dexie enabled"
    DEFAULT_STORAGE=dexie \
    npx --registry=$VERDACCIO_REGISTRY c8 \
        --require source-map-support/register \
        --require @babel/register \
        --reporter=lcov \
        --report-dir="$DEXIE_COVERAGE_REPORT_PATH" \
        mocha \
            --no-bail \
            --expose-gc \
            --config "$MOCHA_CONFIG" \
            ./test_tmp/unit.test.js

    bash ../find-and-move-lcov.sh dexie
fi
set -e