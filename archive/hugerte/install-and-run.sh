#!/bin/bash

cd /coverage_reloaded/repo


yarn global add phantomjs-prebuilt
# Problem: phantomjs-prebuilt uses OpenSSL, but older versions of phantomjs are incompatible with new OpenSSL
# Solution: set OPENSSL_CONF to /dev/null to disable it (https://stackoverflow.com/a/72679175)
export OPENSSL_CONF=/dev/null

yarn install --no-fund --dev

# Problem: this dependency seems to be missing for many tests.
# Solution: add it manually.
yarn add -W @tinymce/oxide-icons-default

# Problem: the default "test" script runs both headless and browser tests. Also, there are two names for headless tests
#          used in the codebase: "headless-test" and "phantomjs-test".
# Solution: check whether "headless-test" or "phantomjs-test" is defined in package.json and run it with nyc to collect coverage.
if yarn run | grep -q "headless-test"; then
    TEST_SCRIPT="headless-test --force"
elif yarn run | grep -q "phantomjs-test"; then
    TEST_SCRIPT="phantomjs-test --force"
else
    echo "Error: No headless test script found in package.json"
    exit 1
fi

echo "Running tests with script: $TEST_SCRIPT"

npx --registry=$WAYPACK_NPM_REGISTRY nyc \
    --reporter=lcov \
    --report-dir="$COVERAGE_REPORT_PATH" \
    yarn $TEST_SCRIPT