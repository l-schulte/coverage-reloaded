#!/bin/bash

cd /coverage_reloaded/repo

# grep -rl "https://github.com" . | xargs sed -i 's|https://github\.com|http://waypack:3000/request/https://github.com|g'

# Problem: The git repo for https://github.com/scottnonnenberg-signal/emoji-panel is no longer available.
# Solution: Replace it with a fork (https://github.com/nzaillian/emoji-panel) that is still available.

sed -i 's|https://github\.com/scottnonnenberg-signal/emoji-panel|https://github\.com/nzaillian/emoji-panel|g' package.json

# Problem: The git repo for https://github.com/Bilb/react-mentions is no longer available.
# Solution: Replace it with a fork (https://github.com/signavio/react-mentions) that is still available.

sed -i 's|https://github\.com/Bilb/react-mentions|https://github\.com/signavio/react-mentions|g' package.json

# Problem: the url "https://github.com/oxen-io/libsession-util-nodejs/releases/download/v0.1.15/libsession_util_nodejs-v0.1.15.tar.gz" is no longer available.
# Solution: replace it with "http://waypack:3000/local/libsession-util-nodejs-0.1.15.tar.gz" which serves the same file.

sed -i 's|https://github\.com/oxen-io/libsession-util-nodejs/releases/download/v0.1.15/libsession_util_nodejs-v0.1.15.tar.gz|http://waypack:3000/local/libsession-util-nodejs-0.1.15.tar.gz|g' package.json
sed -i 's|https://github\.com/oxen-io/libsession-util-nodejs/releases/download/v0.1.15/libsession_util_nodejs-v0.1.15.tar.gz#276b878bbd68261009dd1081b97e25ee6769fd62|http://waypack:3000/local/libsession-util-nodejs-0.1.15.tar.gz|g' yarn.lock


# Problem: node-gyp versions prior to 4 do not support Python 3, which causes native builds to fail.
# Solution: detect the version of node-gyp being used, and if it is less than 4, set the npm config to use Python 2.7 for native builds.
NODEGYP_VERSION=$(grep -A2 '^node-gyp@' yarn.lock | grep 'version' | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

if [ -n "$NODEGYP_VERSION" ]; then
    NODEGYP_MAJOR=$(echo $NODEGYP_VERSION | cut -d. -f1)
    if [ "$NODEGYP_MAJOR" -lt 4 ]; then
        echo "node-gyp $NODEGYP_VERSION detected — setting Python 2.7 for native builds"
        npm config set python /usr/bin/python2.7
        yarn config set python /usr/bin/python2.7
    fi
fi

# Problem: with the fixed dependency files, checksums may fail.
# Solution: clean the yarn cache and disable integrity checks for npm/yarn installs by adding --update-checksums
sed -i '/frozen-lockfile/d' /coverage_reloaded/repo/.yarnrc
yarn cache clean --force
yarn install --no-fund --update-checksums

npm cache clean --force

TRANSPILE_SCRIPT=$(node -p "require('./package.json').scripts['clean-transpile'] || ''")
GRUNT_SCRIPT=$(node -p "require('./package.json').scripts['grunt'] || ''")
BUILDEVERYTHING_SCRIPT=$(node -p "require('./package.json').scripts['build-everything'] || ''")

TEST_NODE_SCRIPT=$(node -p "require('./package.json').scripts['test-node'] || ''")
TEST_SCRIPT=$(node -p "require('./package.json').scripts['test'] || ''")

if [ -n "$TRANSPILE_SCRIPT" ]; then
    echo "Executing transpile script: $TRANSPILE_SCRIPT"
    yarn run clean-transpile
else
    echo "No transpile script found in package.json. Skipping transpilation."
fi

if [ -n "$GRUNT_SCRIPT" ]; then
    echo "Executing grunt script: $GRUNT_SCRIPT"
    yarn run grunt
else
    echo "No grunt script found in package.json. Skipping grunt tasks."
fi

if [ -n "$BUILDEVERYTHING_SCRIPT" ]; then
    echo "Executing build-everything script: $BUILDEVERYTHING_SCRIPT"
    yarn run build-everything
else
    echo "No build-everything script found in package.json. Skipping build tasks."
fi

set +e

echo "Coverage directory: $COVERAGE_REPORT_PATH"

if [ -n "$TEST_NODE_SCRIPT" ]; then
    echo "Executing test-node script: $TEST_NODE_SCRIPT"
    npx --registry=$WAYPACK_NPM_REGISTRY nyc \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        yarn run test-node --no-bail
elif [ -n "$TEST_SCRIPT" ]; then
    echo "Executing test script: $TEST_SCRIPT"
    # test script is what previously was test-node.
    npx --registry=$WAYPACK_NPM_REGISTRY nyc \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        yarn run test --no-bail
else
    echo "No test script found in package.json. Exiting."
    exit 1
fi

TEST_EXIT_CODE=$?
set -e


# This does not work in this project. It exits with a code representing the number of failed tests.
# if [ "$TEST_EXIT_CODE" -eq 1 ]; then
#     echo "WARNING: Tests exited with code $TEST_EXIT_CODE. Coverage may still be collected. Please check test logs for details." >&2
# elif [ "$TEST_EXIT_CODE" -gt 1 ]; then
#     echo "ERROR: Test runner exited with code $TEST_EXIT_CODE, indicating a possible setup issue" >&2
#     exit "$TEST_EXIT_CODE"
# fi