
#!/bin/bash
cd /app/repo

Xvfb :99 -screen 0 1024x768x16 &
export DISPLAY=:99
export CHROMIUM_FLAGS="--no-sandbox --disable-setuid-sandbox"

python ../restore_vscode.py
ls -la .vscode-test/

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