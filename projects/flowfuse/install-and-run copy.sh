#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

cd /coverage_reloaded/repo

print_header 2 "Installing dependencies"

if $IS_YARN_MAIN_PM; then
    yarn install --frozen-lockfile
    PM_RUN="yarn run"
elif $IS_NPM_MAIN_PM; then
    npm install
    PM_RUN="npm run"
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

print_header 2 "Detecting test infrastructure era"

TEST_SCRIPT=$(node -p "p=require('./package.json').scripts; (p.cover || p.test || '')")
COVER_SCRIPT=$(node -p "p=require('./package.json').scripts; (p.cover || '')")
COVER_UNIT_SCRIPT=$(node -p "p=require('./package.json').scripts; (p['cover:unit'] || '')")
COVER_SYSTEM_SCRIPT=$(node -p "p=require('./package.json').scripts; (p['cover:system'] || '')")
TEST_UNIT_FRONTEND_SCRIPT=$(node -p "p=require('./package.json').scripts; (p['test:unit:frontend'] || '')")

print_header 4 "test:               $TEST_SCRIPT"
print_header 4 "cover:              $COVER_SCRIPT"
print_header 4 "cover:unit:         $COVER_UNIT_SCRIPT"
print_header 4 "cover:system:       $COVER_SYSTEM_SCRIPT"
print_header 4 "test:unit:frontend: $TEST_UNIT_FRONTEND_SCRIPT"

HAS_NYC=0
HAS_VITEST=0
HAS_COVER=0
HAS_COVER_SPLIT_DIRS=0
HAS_NPM_RUN_ALL=0

if [ -f .nycrc.json ] || node -e "process.exit(require('./package.json').devDependencies?.nyc ? 0 : 1)" 2>/dev/null; then
    HAS_NYC=1
fi

if echo "$TEST_UNIT_FRONTEND_SCRIPT" | grep -q vitest; then
    HAS_VITEST=1
fi

if [ -n "$COVER_SCRIPT" ]; then
    HAS_COVER=1
fi

# Era 4 uses ./coverage/reports/ subdirectories (detected by cover:report using -t)
if echo "$(node -p "p=require('./package.json').scripts; (p['cover:report'] || '')")" | grep -q "\-t "; then
    HAS_COVER_SPLIT_DIRS=1
fi

if node -e "process.exit(require('./package.json').devDependencies?.['npm-run-all'] ? 0 : 1)" 2>/dev/null; then
    HAS_NPM_RUN_ALL=1
fi

print_header 4 "HAS_NYC=$HAS_NYC  HAS_VITEST=$HAS_VITEST  HAS_COVER=$HAS_COVER  HAS_COVER_SPLIT_DIRS=$HAS_COVER_SPLIT_DIRS  HAS_NPM_RUN_ALL=$HAS_NPM_RUN_ALL"

# Test runner eras (see AGENT.md for full breakdown):
#   Era 1: mocha only, no coverage tooling → wrap with c8
#   Era 2: mocha + nyc (unit + system)
#   Era 3: mocha+nyc (forge) + vitest (frontend) + mocha+nyc (system)
#   Era 4: same as Era 3, split coverage dirs (./coverage/reports/*)

if [ $HAS_COVER -eq 0 ]; then
    print_header 2 "No native coverage tooling detected — installing c8 globally"
    npm install --no-save c8@7
fi

# Forge backend tests start the app server and need frontend/dist/index.html.
print_header 2 "Building frontend assets"
npm run build

print_header 2 "Running tests with coverage"

# IMPORTANT: set +e around test execution so failures don't abort the script.
# Coverage collection (find-and-move-lcov.sh) runs with set -e and must fail loudly.

if [ $HAS_COVER -eq 0 ]; then
    print_header 3 "Era 1: Running mocha tests wrapped with c8"

    TEST_CMD=$(node -p "require('./package.json').scripts.test || ''")

    if [ -n "$TEST_CMD" ] && ! echo "$TEST_CMD" | grep -q "Error: no test specified"; then
        set +e
        npx --registry=$WAYPACK_NPM_REGISTRY c8 --reporter=lcov --reporter=text \
            -- npm run test
        TEST_EXIT=$?
        set -e

        print_header 2 "Collecting coverage reports"
        bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"
    else
        print_header 4 "NOTICE: No valid test script found at this commit — skipping"
    fi

elif [ $HAS_VITEST -eq 0 ]; then
    print_header 3 "Era 2: Running mocha tests with nyc coverage"

    if node -e "process.exit(require('./package.json').scripts['test:unit'] ? 0 : 1)" 2>/dev/null; then
        print_header 3 "Running unit tests (mocha) with nyc..."
        set +e
        npx --registry=$WAYPACK_NPM_REGISTRY nyc --reporter=lcov npm run test:unit
        UNIT_EXIT=$?
        set -e

        print_header 2 "Collecting unit test coverage reports"
        bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
    else
        print_header 4 "NOTICE: No test:unit script found — skipping unit tests"
    fi

    if node -e "process.exit(require('./package.json').scripts['test:system'] ? 0 : 1)" 2>/dev/null; then
        print_header 3 "Running system tests (mocha) with nyc..."
        set +e
        npx --registry=$WAYPACK_NPM_REGISTRY nyc --reporter=lcov --no-clean npm run test:system
        SYSTEM_EXIT=$?
        set -e

        print_header 2 "Collecting system test coverage reports"
        bash /coverage_reloaded/find-and-move-lcov.sh "system" "false" "$SYSTEM_EXIT"
    else
        print_header 4 "NOTICE: No test:system script found -- skipping system tests"
    fi

else
    print_header 3 "Eras 3/4: Running mocha (forge) + vitest (frontend) + mocha (system)"

    if node -e "process.exit(require('./package.json').scripts['test:unit:forge'] ? 0 : 1)" 2>/dev/null; then
        print_header 3 "Running forge unit tests (mocha) with nyc..."

        set +e
        npx --registry=$WAYPACK_NPM_REGISTRY nyc --reporter=lcov npm run test:unit:forge -- --exit
        FORGE_UNIT_EXIT=$?
        set -e

        print_header 2 "Collecting forge unit coverage reports"
        bash /coverage_reloaded/find-and-move-lcov.sh "forge-unit" "false" "$FORGE_UNIT_EXIT"
    else
        print_header 4 "NOTICE: No test:unit:forge script found — skipping forge unit tests"
    fi

    if node -e "process.exit(require('./package.json').scripts['test:unit:frontend'] ? 0 : 1)" 2>/dev/null; then
        print_header 3 "Running frontend unit tests (vitest) with coverage..."

        # Coverage provider c8 is missing for some commits.
        print_header 4 "Installing @vitest/coverage-c8..."
        npm install --no-save --legacy-peer-deps @vitest/coverage-c8

        set +e
        npx --registry=$WAYPACK_NPM_REGISTRY vitest run --config ./config/vitest.config.ts \
            --coverage.enabled --coverage.reporter=lcov --reporter=verbose
        FRONTEND_EXIT=$?
        set -e

        print_header 2 "Collecting frontend coverage reports"
        bash /coverage_reloaded/find-and-move-lcov.sh "frontend-unit" "false" "$FRONTEND_EXIT"
    else
        print_header 4 "NOTICE: No test:unit:frontend script found — skipping frontend tests"
    fi

    if node -e "process.exit(require('./package.json').scripts['test:system'] ? 0 : 1)" 2>/dev/null; then
        print_header 3 "Running system tests (mocha) with nyc..."

        set +e
        npx --registry=$WAYPACK_NPM_REGISTRY nyc --reporter=lcov --no-clean npm run test:system
        SYSTEM_EXIT=$?
        set -e

        print_header 2 "Collecting system test coverage reports"
        bash /coverage_reloaded/find-and-move-lcov.sh "system" "false" "$SYSTEM_EXIT"
    else
        print_header 4 "NOTICE: No test:system script found — skipping system tests"
    fi
fi

print_header 1 "FlowFuse coverage run complete"
