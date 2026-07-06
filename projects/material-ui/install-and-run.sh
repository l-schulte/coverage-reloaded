#!/bin/bash

source /coverage_reloaded/logging.sh

set -e

cd /coverage_reloaded/repo


if $IS_NPM_MAIN_PM; then
    print_header 2 "Installing dependencies with npm..."
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-fund --include=dev

    COMMAND="npm run"
elif $IS_YARN_MAIN_PM; then
    # Requires a non-existing dependency (vitest-mui, was deleted from registry)
    # Workaround: providing the file (vitest-mui-0.3.3.tgz and vitest-mui-0.3.4.tgz) in the waypack machine
    # Integrity checks fail for this file.
    # Workaround: clean cache with yarn cache clean disable integrity checks for yarn installs by adding --update-checksums
    print_header 2 "Installing dependencies with yarn..."
    yarn cache clean --force
    yarn install --update-checksums --ignore-engines

    COMMAND="yarn run"
elif $IS_PNPM_MAIN_PM; then
    print_header 2 "Installing dependencies with pnpm..."
    pnpm install

    COMMAND="pnpm run"
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

set +e

print_header 2 "Running tests with coverage"

# Prevent Node.js from reparsing ambiguous .js files as ESM (which breaks __dirname usage)
# Only needed on Node >=20 where --experimental-detect-module is default
if [ "$(node -e "console.log(process.version.substring(1).split('.')[0])")" -ge 20 ] 2>/dev/null; then
    print_header 4 "Node.js version is >=20, setting NODE_OPTIONS"
    if ! grep -q "no-experimental-detect-module" .mocharc.js 2>/dev/null; then
        print_header 4 "...adding --no-experimental-detect-module to NODE_OPTIONS (not in .mocharc.js file)"
        export NODE_OPTIONS="$NODE_OPTIONS --no-experimental-detect-module"
    fi

    # print_header 4 "...adding --no-experimental-require-module to NODE_OPTIONS"
    # export NODE_OPTIONS="$NODE_OPTIONS --no-experimental-require-module"
fi

HAS_COVERAGE_SCRIPT=$(jq -r '.scripts["test:coverage"] // empty' package.json)
if [ -z "$HAS_COVERAGE_SCRIPT" ]; then
    print_header 2 "NOT APPLICABLE: No test:coverage script found in package.json. Skipping coverage collection."
    exit 2
fi

set -o pipefail
OUTPUT=$($COMMAND test:coverage 2>&1 | tee /dev/stderr)
EXIT_CODE=${PIPESTATUS[0]}
set -e

if echo "$OUTPUT" | grep -q 'Exception during run:'; then
    print_header 4 "ERROR: Mocha aborted mid-run (Exception during run:) — coverage is partial, not generating lcov"
    rm -rf .nyc_output
    EXIT_CODE=1
else
    npx --registry=$VERDACCIO_REGISTRY nyc report --reporter=lcov
fi

bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$EXIT_CODE"