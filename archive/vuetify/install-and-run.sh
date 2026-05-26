#!/bin/bash

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

# ═══════════════════════════════════════════════════════════════════════════════
# VUETIFY COVERAGE COLLECTION
#
# Vuetify evolved through several eras:
#
#   Era        | PM         | Test runner | Coverage              | Approx years
#  ────────────┼────────────┼─────────────┼───────────────────────┼─────────────
#   Yarn+Jest  | yarn@1.x   | jest        | jest --coverage        | 2019-2022
#   Yarn+Jest  | yarn@1.x   | jest        | jest --coverage        | 2022-2023
#   pnpm       | pnpm@9-10  | jest        | jest --coverage        | 2024-2025
#
# Test types found in the project:
#   - Unit tests (Jest/Vitest)     → primary coverage source ✅
#   - Cypress component tests (mid-era) → collected via separate script ⚙️
#   - Cypress E2E (kitchen, early) → not collected ❌
#
# The main test suite lives in packages/vuetify/.
# In the yarn era, Lerna orchestrated workspace commands.
# In the pnpm era, pnpm workspaces and lerna-lite are used.
#
# Cypress coverage collection is delegated to cypress-coverage-setup.sh
# ═══════════════════════════════════════════════════════════════════════════════

# ── Dependency Installation ───────────────────────────────────────────────────

print_header 2 "Installing dependencies"

if $IS_NPM_MAIN_PM; then
    echo "ERROR: Vuetify does not use npm as package manager"
    exit 1

elif $IS_YARN_MAIN_PM; then
    # ── Yarn v1 era ──────────────────────────────────────────────────────────
    # Yarn v1 is used for the vast majority of commits (~90%).
    # Some commits have a yarn.lock, others rely on lerna for bootstrapping.

    print_header 3 " Installing dependencies with yarn..."

    # Clean cache first to prevent stale integrity issues
    yarn cache clean --force 2>/dev/null || true

    # Try frozen install first; fall back to regular install
    if [ -f yarn.lock ]; then
        yarn install --frozen-lockfile --update-checksums 2>&1 || \
        yarn install --update-checksums 2>&1
    else
        yarn install 2>&1
    fi

    # Lerna bootstrap for monorepo linking (lerna is in devDependencies)
    if [ -f lerna.json ]; then
        print_header 3 " Bootstrapping with lerna..."
        npx lerna bootstrap 2>&1 || true
    fi

    PM_RUN="yarn run"
    MONOREPO_RUN="lerna run"

elif $IS_PNPM_MAIN_PM; then
    # ── pnpm era ─────────────────────────────────────────────────────────────
    # Recent commits use pnpm workspaces. The pnpm-lock.yaml is the lock file.
    # Lerna-lite may also be present but is mainly for versioning/publishing.

    print_header 3 " Installing dependencies with pnpm..."

    # Try frozen install first; fall back to regular install
    if [ -f pnpm-lock.yaml ]; then
        pnpm install --frozen-lockfile 2>&1 || \
        pnpm install 2>&1
    else
        pnpm install 2>&1
    fi

    PM_RUN="pnpm run"
    MONOREPO_RUN="pnpm run -r"

else
    print_header 2 "ERROR" "No main package manager detected"
    exit 1
fi

# ── Ensure cross-env is available ─────────────────────────────────────────────
# cross-env is a root-level devDependency used in many test/build scripts
# (e.g. "cross-env NODE_ENV=test jest"). Workspace commands run from
# packages/vuetify/ may not have root devDependencies on their PATH.
# Install it globally to be safe.

print_header 2 "Ensuring cross-env availability"

if ! command -v cross-env &>/dev/null; then
    print_header 3 " cross-env not found globally, installing..."
    npm install --no-fund -g cross-env 2>&1 | tail -1
else
    print_header 3 " cross-env already available"
fi

# Also ensure it's in node_modules/.bin (workspace context) by installing
# it as a direct dependency if not already present
if ! node -e "require.resolve('cross-env')" 2>/dev/null; then
    print_header 3 " cross-env not in local node_modules, installing..."
    npm install --no-save --no-fund cross-env 2>&1 | tail -1
fi

# ── Era Detection ─────────────────────────────────────────────────────────────

print_header 2 "Detecting test infrastructure era"

cd packages/vuetify

IS_JEST=$(node -e "try { require.resolve('jest'); console.log('true'); } catch { console.log('false'); }")
HAS_TEST_COVERAGE_SCRIPT=$(node -e "try { const p=require('./package.json'); console.log(!!(p.scripts && p.scripts['test:coverage'])) } catch { console.log('false') }" 2>/dev/null)

echo "IS_JEST:                    $IS_JEST"
echo "HAS_TEST_COVERAGE_SCRIPT:   $HAS_TEST_COVERAGE_SCRIPT"

cd /coverage_reloaded/repo

# ── Run Tests with Coverage ───────────────────────────────────────────────────

mkdir -p coverage

set +e

cd packages/vuetify

# Track overall exit status — if at least one runner succeeds, consider it OK
GLOBAL_TEST_EXIT=1

# Run all applicable test runners sequentially so we can collect coverage
# from each one. find-and-move-lcov.sh uses TEST_TYPE to name files
# separately (e.g. test_coverage.lcov.info, jest.lcov.info), which are merged
# later in execute.sh.

# ── 1. test:coverage script (if available) ─────────────────────────────────
# This is the project's own coverage script. It typically delegates to
# jest internally. We run it first as it's the most authoritative.

if [ "$HAS_TEST_COVERAGE_SCRIPT" = "true" ]; then
    print_header 2 "Using test:coverage script"

    if $IS_PNPM_MAIN_PM; then
        pnpm run test:coverage 2>&1
        TEST_EXIT=$?
    else
        yarn run test:coverage 2>&1
        TEST_EXIT=$?
    fi

    # Collect coverage produced by test:coverage
    bash /coverage_reloaded/find-and-move-lcov.sh "test_coverage" "true"
    if [ $TEST_EXIT -eq 0 ]; then
        GLOBAL_TEST_EXIT=0
    fi
fi



# ── 2. Jest (if available and not already covered by test:coverage) ────────
# Only run Jest directly if test:coverage didn't already produce coverage
# (test:coverage typically delegates to jest in the yarn era anyway).

if [ "$IS_JEST" = "true" ] && [ "$HAS_TEST_COVERAGE_SCRIPT" != "true" ]; then
    print_header 2 "Running jest with coverage"

    cross-env NODE_ENV=test npx jest --coverage --coverageReporters=lcov --no-cache 2>&1
    JEST_EXIT=$?

    # Collect coverage produced by jest
    bash /coverage_reloaded/find-and-move-lcov.sh "jest" "true"
    if [ $JEST_EXIT -eq 0 ]; then
        GLOBAL_TEST_EXIT=0
    fi
fi

# ── 3. Cypress Component Tests ─────────────────────────────────────────────
# Mid-era commits (2021-05 to 2024-09) use Cypress component testing.
# Coverage from Cypress requires the @cypress/code-coverage plugin.
#
# Detection is file-based:
#   Era A (v8,  2021-05 to 2022-06): cypress.json + cypress/plugins/index.js
#   Era B (v10+, 2022-06 to 2024-09): cypress.config.ts + cypress/plugins/index.cjs
#
# The actual detection, injection, and execution is delegated to the
# separate cypress-coverage-setup.sh script for readability.

print_header 2 "Checking for Cypress"

# Source the helper from the project directory (it runs detection internally)
bash /coverage_reloaded/cypress-coverage-setup.sh
CYPRESS_EXIT=$?

if [ $CYPRESS_EXIT -eq 0 ]; then
    GLOBAL_TEST_EXIT=0
else 
    print_header 3 "Cypress returned exit code $CYPRESS_EXIT, may be an error or just failing tests."
fi

cd /coverage_reloaded/repo/packages/vuetify

# ── 4. No test infrastructure found ──────────────────────────────────────────
# Neither test:coverage, jest, nor Cypress yielded usable coverage.
# Fail loudly to avoid recording incomplete/bad coverage data.

# First, detect Cypress config presence for the fallback message
CYPRESS_CONFIG_PRESENT="false"
if [ -f cypress.config.ts ] || [ -f cypress.config.js ] || [ -f cypress.config.mjs ] || [ -f cypress.json ]; then
    CYPRESS_CONFIG_PRESENT="true"
fi

if [ "$HAS_TEST_COVERAGE_SCRIPT" != "true" ] && [ "$IS_JEST" != "true" ] && [ "$CYPRESS_CONFIG_PRESENT" != "true" ]; then
    echo "ERROR: No test infrastructure detected (no test:coverage script, no jest, no cypress)"
    echo "       Cannot collect coverage for this commit."
    GLOBAL_TEST_EXIT=1
fi

set -e
