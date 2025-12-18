
#!/bin/bash
cd /app/repo

Xvfb :99 -screen 0 1024x768x16 &
export DISPLAY=:99
export CHROMIUM_FLAGS="--no-sandbox --disable-setuid-sandbox"

python ../restore_vscode.py
ls -la .vscode-test/

# There may be a package-lock.json file with resolved URLs hardcoded to npmjs.org. Slow and potentially rate limited.
# Workaround 1: remove URLs
# Result: fails (TypeError [ERR_INVALID_ARG_TYPE]: The "paths[1]" argument must be of type string. Received undefined)
# [ -f "package-lock.json" ] && sed -i '/"resolved":/d' package-lock.json

# Workaround 2: replace URLs with waypack URL (https://registry.npmjs.org/)
# Result: works
[ -f "package-lock.json" ] && sed -i 's#"resolved": "https://registry.npmjs.org/#"resolved": "http://waypack:3000/npm/'"$timestamp"'/#g' package-lock.json

npm install --no-fund

set +e
# Between c8 and nyc, nyc seems to produce better reports for vscode extensions.
# Specifically, c8 does not generate reports if tests fail, while nyc does.
# c8 would need to be installed: npm install c8 --no-fund
#
# npx c8 --r=lcov -o ../$COVERAGE_REPORT_PATH npm run test

npx nyc \
    --temp-directory="$COVERAGE_REPORT_PATH/nyc" \
    --reporter=lcov \
    --report-dir="$COVERAGE_REPORT_PATH/lcov" \
    npm run test

set -e

python ../store_vscode.py