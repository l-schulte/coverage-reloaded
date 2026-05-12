#!/bin/bash
cd /coverage_reloaded/repo

npm ci --no-fund
npm install -g nyc --no-fund

# Choosing to use nyc in both cases (for consistency with "aws-toolkit-vscode").
# In principle, c8 would work in "spreed".
# c8 would need to be installed:  npm install c8 --no-fund
#
# npx c8 --r=lcov -o ../$COVERAGE_REPORT_PATH npm run test:unit
# npx c8 --r=lcov -o ../$COVERAGE_REPORT_PATH npm run test

# set +e
echo "Running tests with coverage script..."
npm run test -- --coverage.enabled=true --coverage.reporter=lcov

bash ../find-and-move-lcov.sh
# set -e