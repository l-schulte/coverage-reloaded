#!/usr/bin/env bash
set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit"
    exit 2
fi

if [ ! -d packages/language-server ]; then
    print_header 2 "NOT APPLICABLE" "No packages/language-server at this commit"
    exit 2
fi

# ── Dependency installation ───────────────────────────────────────────────────

print_header 2 "Installing dependencies"

if [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    pnpm install
elif [ "$IS_NPM_MAIN_PM" = "true" ]; then
    npm install
    # npm-era orchestration uses lerna to install each workspace package.
    # lerna bails by default; the project's bootstrap script invokes `lerna exec
    # npm install` which must run with --no-bail so one failing subpackage does
    # not abort the whole install.
    if node -p "!!((require('./package.json').scripts||{}).bootstrap)"; then
        npx --registry=$WAYPACK_NPM_REGISTRY lerna exec --no-bail -- npm install
    fi
elif [ "$IS_YARN_MAIN_PM" = "true" ]; then
    yarn install
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

# ── Unit suite: packages/language-server ─────────────────────────────────────
# History (command_changes.csv, branched on what the commit contains):
#   2021-01-04 → 2022-07-18  mocha  (compiled dist, sourceMap:true)  no coverage
#   2022-07-19 → 2024-05-14  nyc + mocha  (clover + text-summary)
#   2024-05-15 → present      vitest + @vitest/coverage-v8 (v8/clover)
# Test dir: dist/src/test before 2022-03-23, dist/src/__test__ after.

cd /coverage_reloaded/repo/packages/language-server

LS_TEST_SCRIPT=$(node -p "((require('./package.json').scripts||{}).test) || ''")
HAS_VITEST_CONFIG=$([ -f vitest.config.mts ] && echo "true" || echo "false")

suite_start "unit" "language-server behavioral tests with coverage"

set +e
if echo "$LS_TEST_SCRIPT" | grep -q "vitest"; then
    print_header 3 "vitest era detected"
    npx --registry=$WAYPACK_NPM_REGISTRY vitest run \
        --coverage.enabled \
        --coverage.reporter=clover \
        --coverage.reporter=lcov \
        --coverage.reportsDirectory=coverage \
        --poolOptions.threads.minThreads=1 \
        --poolOptions.threads.maxThreads=1
    TEST_EXIT=$?
elif echo "$LS_TEST_SCRIPT" | grep -q "nyc"; then
    print_header 3 "nyc era detected (project-configured coverage)"
    npm test
    npx nyc report --reporter=lcovonly
    TEST_EXIT=$?
else
    print_header 3 "mocha era detected (wrap with nyc to produce lcov)"
    npm run build
    # The native prisma-fmt engine (2021-01 → 2021-12) was downloaded at test
    # time from binaries.prisma.sh. Mocha's default 2s hook timeout is too short
    # for a cold download, which skipped the completion suite and left a
    # partially-written, non-executable binary. Route the download through
    # WayPack's cached /request/ proxy so it is local and fast.
    WAYPACK_REQUEST_BASE="http://waypack:3000/request"
    if grep -rlq --include='*.js' 'https://binaries.prisma.sh' dist; then
        print_header 3 "Routing prisma-fmt engine downloads through WayPack cache"
        grep -rl --include='*.js' 'https://binaries.prisma.sh' dist \
          | while IFS= read -r f; do
                sed -i "s#https://binaries.prisma.sh#${WAYPACK_REQUEST_BASE}/https://binaries.prisma.sh#g" "$f"
            done
    fi
    if [ -d dist/src/__test__ ]; then
        GLOB='./dist/src/__test__/**/*.test.js'
    else
        GLOB='./dist/src/test/**/*.test.js'
    fi
    npx --registry=$VERDACCIO_REGISTRY nyc@15 --reporter=lcovonly --reporter=text-summary \
        mocha --ui tdd --useColors true "$GLOB"
    TEST_EXIT=$?
fi
set -e

bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"
suite_end "unit" "$TEST_EXIT"

cd /coverage_reloaded/repo

# ── Scripts suite: root scripts/__tests__ ─────────────────────────────────────
# Release-tooling tests. Runs once a config exists at the commit: jest.config.js
# from 2021-09-30 (before 2022-07-19 it had no coverage config, so coverage is
# forced via CLI flags), then scripts/vitest.config.mjs from 2025-12-17.
# Skipped on earlier commits (no config => not the project's intent).

HAS_VITEST_SCRIPTS=$([ -f scripts/vitest.config.mjs ] && echo "true" || echo "false")
HAS_JEST_CONFIG=$([ -f jest.config.js ] && echo "true" || echo "false")
JEST_HAS_COVERAGE=$([ -f jest.config.js ] && grep -qE 'collectCoverage|coverageReporters|coverageDirectory|collectCoverageFrom' jest.config.js && echo "true" || echo "false")

if [ "$HAS_VITEST_SCRIPTS" = "true" ] || [ "$HAS_JEST_CONFIG" = "true" ]; then
    set +e
    if [ "$HAS_VITEST_SCRIPTS" = "true" ]; then
        suite_start "vitest" "npx vitest run scripts/__tests__ with coverage"
        print_header 3 "vitest scripts era detected"
        npx --registry=$WAYPACK_NPM_REGISTRY vitest run \
            --config scripts/vitest.config.mjs \
            --coverage.enabled \
            --coverage.reporter=clover \
            --coverage.reporter=lcov \
            --coverage.reportsDirectory=scripts/__tests__/coverage \
            --poolOptions.threads.minThreads=1 \
            --poolOptions.threads.maxThreads=1
        TEST_EXIT=$?
        set -e
        bash /coverage_reloaded/find-and-move-lcov.sh "vitest" "false" "$TEST_EXIT"
        suite_end "vitest" "$TEST_EXIT"
    else
        suite_start "jest" "npm run testScripts with coverage"
        if [ "$JEST_HAS_COVERAGE" = "true" ]; then
            npm run testScripts -- \
                --coverageReporters=clover \
                --coverageReporters=lcov \
                --maxWorkers=1
        else
            # jest.config.js before 2022-07-19 had no coverage config; force it
            # so the release-tooling suite also yields an lcov file.
            npm run testScripts -- \
                --coverage \
                --collectCoverageFrom='scripts/**/*.js' \
                --collectCoverageFrom='!**/__tests__/**/*' \
                --coverageReporters=clover \
                --coverageReporters=lcov \
                --coverageDirectory=scripts/__tests__/coverage \
                --maxWorkers=1
        fi
        TEST_EXIT=$?
        set -e
        bash /coverage_reloaded/find-and-move-lcov.sh "jest" "false" "$TEST_EXIT"
        suite_end "jest" "$TEST_EXIT"
    fi
else
    print_header 3 "scripts-tests suite SKIPPED — no coverage config (jest.config.js / scripts/vitest.config.mjs) at this commit"
fi

print_header 1 "language-tools coverage run complete"
