#!/bin/bash

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
    MOCHA_COVERAGE_REPORT_PATH="$COVERAGE_REPORT_PATH/co_re_mocha"
    echo "Running tests with mocha enabled (coverage report will be saved to $MOCHA_COVERAGE_REPORT_PATH)"
    npx --registry=$WAYPACK_NPM_REGISTRY c8 \
        --require source-map-support/register \
        --require @babel/register \
        --reporter=lcov \
        --report-dir="$MOCHA_COVERAGE_REPORT_PATH" \
        mocha \
            --no-bail \
            --expose-gc \
            --config "$MOCHA_CONFIG" \
            ./test_tmp/unit.test.js
fi
if [[ "$TEST_SCRIPT" == *"test:node:lokijs"* ]]; then
    LOKIJS_COVERAGE_REPORT_PATH="$COVERAGE_REPORT_PATH/co_re_lokijs"
    echo "Running tests with lokijs enabled (coverage report will be saved to $LOKIJS_COVERAGE_REPORT_PATH)"
    DEFAULT_STORAGE=lokijs \
    npx --registry=$WAYPACK_NPM_REGISTRY c8 \
        --require source-map-support/register \
        --require @babel/register \
        --reporter=lcov \
        --report-dir="$LOKIJS_COVERAGE_REPORT_PATH" \
        mocha \
            --no-bail \
            --expose-gc \
            --config "$MOCHA_CONFIG" \
            ./test_tmp/unit.test.js
fi
if [[ "$TEST_SCRIPT" == *"test:node:pouchdb"* ]]; then
    POUCHDB_COVERAGE_REPORT_PATH="$COVERAGE_REPORT_PATH/co_re_pouchdb"
    echo "Running tests with pouchdb enabled (coverage report will be saved to $POUCHDB_COVERAGE_REPORT_PATH)"
    DEFAULT_STORAGE=pouchdb \
    npx --registry=$WAYPACK_NPM_REGISTRY c8 \
        --require source-map-support/register \
        --require @babel/register \
        --reporter=lcov \
        --report-dir="$POUCHDB_COVERAGE_REPORT_PATH" \
        mocha \
            --no-bail \
            --expose-gc \
            --config "$MOCHA_CONFIG" \
            ./test_tmp/unit.test.js
fi
if [[ "$TEST_SCRIPT" == *"test:node:dexie"* ]]; then
    DEXIE_COVERAGE_REPORT_PATH="$COVERAGE_REPORT_PATH/co_re_dexie"
    echo "Running tests with dexie enabled (coverage report will be saved to $DEXIE_COVERAGE_REPORT_PATH)"
    DEFAULT_STORAGE=dexie \
    npx --registry=$WAYPACK_NPM_REGISTRY c8 \
        --require source-map-support/register \
        --require @babel/register \
        --reporter=lcov \
        --report-dir="$DEXIE_COVERAGE_REPORT_PATH" \
        mocha \
            --no-bail \
            --expose-gc \
            --config "$MOCHA_CONFIG" \
            ./test_tmp/unit.test.js
fi
set -e