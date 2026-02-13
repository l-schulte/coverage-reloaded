#!/bin/bash
cd /coverage_reloaded/repo

Xvfb :99 -screen 0 1024x768x16 &
export DISPLAY=:99
export CHROMIUM_FLAGS="--no-sandbox --disable-setuid-sandbox"

# Problem: the url for "react-tag-autocomplete": "https://github.com/mispy/react-tags" does not exist.
# Solution: replace it with "react-tag-autocomplete": "*", so that it is resolved through the registry (waypack-verdaccio) instead.
sed -i 's|"react-tag-autocomplete": "https://github.com/mispy/react-tags"|"react-tag-autocomplete": "*"|g' package.json

# Problem: owid-grapher mixes npm, yarn, and multiple test scrits.
# Solution: setup is complex.
if $IS_NPM_MAIN_PM; then
    # Does not work... will be downloaded every time.
    # # Problem: cypress downloads a binary during installation, which causes issues with caching and reproducibility.
    # # Solution: install cypress with --ignore-scripts to skip the binary download, and then replace the url by searching 
    # #           for it (https://cdn.cypress.io) in all node_modules/cypress files and replacing it with the registry url,
    # #           which will be cached by waypack, i.e., http://waypack:3000/request/https://cdn.cypress.io
    # npm install cypress --ignore-scripts
    # for file in node_modules/cypress/*; do
    #     sed -i 's|https://cdn.cypress.io|http://waypack:3000/request/https://cdn.cypress.io|g' "$file"
    # done
    # cd node_modules/cypress && npm run postinstall
    npm install --legacy-peer-deps

    COMMAND="npm run"
elif $IS_YARN_MAIN_PM; then
    # Does not work... will be downloaded every time.
    # # Problem: cypress downloads a binary during installation, which causes issues with caching and reproducibility.
    # # Solution: install cypress with --ignore-scripts to skip the binary download, and then replace the url by searching 
    # #           for it (https://cdn.cypress.io) in all node_modules/cypress files and replacing it with the registry url,
    # #           which will be cached by waypack, i.e., http://waypack:3000/request/https://cdn.cypress.io
    # yarn add cypress --ignore-scripts
    # for file in node_modules/cypress/*; do
    #     sed -i 's|https://cdn.cypress.io|http://waypack:3000/request/https://cdn.cypress.io|g' "$file"
    # done
    # cd node_modules/cypress && npm run postinstall
    yarn install --legacy-peer-deps

    COMMAND="yarn run"
fi

set +e

if grep -q '"test"' package.json; then
    echo "Running tests with npx and test script..."
    npx --registry=$WAYPACK_NPM_REGISTRY nyc \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        --force \
        -- $COMMAND test
else
    echo "No default test script found in package.json, checking for testJest or testCypress scripts..."
    if grep -q "testJest" package.json; then
        echo "Running tests with testJest script..."
        $COMMAND testJest -- --coverage.enabled=true --coverage.reporter=lcov --coverageDirectory="$COVERAGE_REPORT_PATH/co_re!_sub_jest" --passWithNoTests
    fi
    if grep -q "testCypress" package.json; then
        echo "Running tests with testCypress script..."
        npx --registry=$WAYPACK_NPM_REGISTRY nyc \
            --reporter=lcov \
            --report-dir="$COVERAGE_REPORT_PATH/co_re!_sub_cypress" \
            --force \
            -- $COMMAND testCypress
    fi    
fi

set -e