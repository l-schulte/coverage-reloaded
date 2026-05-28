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
#   V1 (yarn)  | yarn@1.x   | jest        | test:unix --coverage   | 2019-2023
#   V1 (pnpm)  | pnpm@9-10  | jest        | test:unix --coverage   | 2024-2025
#   V2 (pnpm)  | pnpm@9-10  | vitest      | vitest --coverage      | 2025-
#
# Runner detection:
#   V1: test script = "node build/run-tests.js"
#       → dispatches to test:unix (cross-env NODE_ENV=test jest)
#       → we run test:unix --coverage directly
#   V2: test script = "vitest"
#       → we run vitest --coverage directly
#
# Test types found in the project:
#   - Unit tests (Jest via V1, or Vitest via V2) → primary coverage source ✅
#   - Cypress component tests (mid-era) → now collected via patching ✅
#   - Cypress E2E (kitchen, early) → now collected via patching ✅
#
# The main test suite lives in packages/vuetify/.
# In the yarn era, Lerna orchestrated workspace commands.
# In the pnpm era, pnpm workspaces and lerna-lite are used.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Cypress Coverage Config Patching ─────────────────────────────────────────
# Before installing dependencies, apply coverage-enabled patches to any
# Cypress configuration files found at this commit. The patcher compares
# file content SHA256 hashes against known originals and replaces matches
# with coverage-enabled versions.
#
# Configs from 4 eras are handled:
#   - packages/vuetify/cypress.config.ts     (Cypress 10+, vite)
#   - packages/vuetify/cypress.json           (pre-Cypress 10, webpack)
#   - packages/vuetify/cypress/plugins/*     (pre-Cypress 10 plugins)
#   - packages/vuetify/cypress/support/*     (support files)
#   - packages/kitchen/cypress.json           (kitchen E2E, early era)
#   - packages/kitchen/cypress/plugins/*     (kitchen plugins)
#   - packages/kitchen/cypress/support/*     (kitchen support)

print_header 2 "Applying Cypress coverage patches"

CONFIG_DIR="/coverage_reloaded/cypress-coverage-configs"
if [ -d "$CONFIG_DIR" ] && [ -f "$CONFIG_DIR/mapper.tsv" ] && [ -d "$CONFIG_DIR/patches" ]; then
    bash /coverage_reloaded/cypress-patcher.sh \
        /coverage_reloaded/repo \
        "$CONFIG_DIR/mapper.tsv" \
        "$CONFIG_DIR/patches"
else
    print_header 3 "  No Cypress coverage configs found — skipping patching"
fi

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

# ── Ensure @cypress/code-coverage is available ────────────────────────────────
# The Cypress coverage patches reference @cypress/code-coverage for task
# registration and support imports. Install it as a devDependency so it's
# available at runtime for any commit that has Cypress configs patched.
# Cypress itself should come from the project's own devDependencies (it was
# a devDependency during the mid-era commits that used Cypress testing).

print_header 2 "Ensuring @cypress/code-coverage availability"

# Check if @cypress/code-coverage is already installed (from project deps)
if ! node -e "try { require.resolve('@cypress/code-coverage'); console.log('found') } catch(e) { process.exit(1) }" 2>/dev/null; then
    print_header 3 "  @cypress/code-coverage not found, installing..."
    if $IS_PNPM_MAIN_PM; then
        pnpm add --save-dev @cypress/code-coverage 2>&1 | tail -5 || true
    elif $IS_YARN_MAIN_PM; then
        # yarn workspaces require -W flag to install at root level
        yarn add --dev @cypress/code-coverage -W 2>&1 | tail -5 || \
        yarn add --dev @cypress/code-coverage --ignore-workspace-root-check 2>&1 | tail -5 || true
    else
        npm install --no-save --no-fund @cypress/code-coverage 2>&1 | tail -5 || true
    fi
else
    print_header 3 "  @cypress/code-coverage already available"
fi

# ── Ensure vite-plugin-istanbul is available ──────────────────────────────────
# The Cypress coverage patches for Vite-based projects (Cypress 10+ era) add
# vite-plugin-istanbul to the Vite config to instrument source code for
# Istanbul coverage collection. Without this plugin, the browser code has no
# __coverage__ instrumentation and no coverage data is collected.
#
# This is only needed for commits that use Vite as the Cypress dev server
# bundler (detected by the presence of vite.config.* files).

print_header 2 "Ensuring vite-plugin-istanbul availability"

if ! node -e "try { require.resolve('vite-plugin-istanbul'); console.log('found') } catch(e) { process.exit(1) }" 2>/dev/null; then
    print_header 3 "  vite-plugin-istanbul not found, installing..."
    if $IS_PNPM_MAIN_PM; then
        pnpm add --save-dev vite-plugin-istanbul 2>&1 | tail -5 || true
    elif $IS_YARN_MAIN_PM; then
        yarn add --dev vite-plugin-istanbul -W 2>&1 | tail -5 || \
        yarn add --dev vite-plugin-istanbul --ignore-workspace-root-check 2>&1 | tail -5 || true
    else
        npm install --no-save --no-fund vite-plugin-istanbul 2>&1 | tail -5 || true
    fi
else
    print_header 3 "  vite-plugin-istanbul already available"
fi

# ── Era Detection ─────────────────────────────────────────────────────────────
#
# We detect the test runner from the `test` script in packages/vuetify/package.json.
# Two distinct variants exist:
#
#   V1 (yarn era + early pnpm era):
#     test = node build/run-tests.js
#     test:unix = cross-env NODE_ENV=test jest   (or NODE_ENV=test jest)
#     → run test:unix with --coverage
#
#   V2 (later pnpm era):
#     test = vitest
#     → run vitest with --coverage

print_header 2 "Detecting test runner"

cd packages/vuetify

TEST_SCRIPT=$(node -e "try { const p=require('./package.json'); console.log(p.scripts && p.scripts['test'] || ''); } catch { console.log(''); }" 2>/dev/null)

IS_V1=false
IS_V2=false

if echo "$TEST_SCRIPT" | grep -q "node build/run-tests.js"; then
    IS_V1=true
    echo "Detected V1: test = node build/run-tests.js → running Jest directly"
elif echo "$TEST_SCRIPT" | grep -q "vitest"; then
    IS_V2=true
    echo "Detected V2: test = vitest → running Vitest directly"
else
    echo "WARNING: Unknown test script definition: $TEST_SCRIPT"
    echo "Falling back to legacy detection..."
    IS_JEST=$(node -e "try { require.resolve('jest'); console.log('true'); } catch { console.log('false'); }")
    HAS_TEST_COVERAGE_SCRIPT=$(node -e "try { const p=require('./package.json'); console.log(!!(p.scripts && p.scripts['test:coverage'])) } catch { console.log('false') }" 2>/dev/null)
fi

echo "TEST_SCRIPT:              $TEST_SCRIPT"
echo "IS_V1:                    $IS_V1"
echo "IS_V2:                    $IS_V2"

cd /coverage_reloaded/repo

# ── Run Tests with Coverage ───────────────────────────────────────────────────

mkdir -p coverage

set +e

cd packages/vuetify

# Track whether any test runner was executed and whether all of them that ran
# produced coverage. We ignore test runner exit codes (they can indicate single
# test failures without affecting coverage collection). Instead, we rely on
# find-and-move-lcov.sh: if a runner was executed but produced no coverage
# files, that's a real error.
RAN_ANY_TEST=false
COVERAGE_FAILURE=false

# Run all applicable test runners sequentially so we can collect coverage
# from each one. find-and-move-lcov.sh uses TEST_TYPE to name files
# separately (e.g. test_coverage.lcov.info, jest.lcov.info), which are merged
# later in execute.sh.

# ── 1. V1: Jest (yarn era + early pnpm era) ───────────────────────────────
# test = node build/run-tests.js → internally dispatches to test:unix.
# We run Jest directly with coverage. We're always on Linux (Debian 11 in
# the Docker container), so cross-env is unnecessary — just set NODE_ENV.

if [ "$IS_V1" = "true" ]; then
    RAN_ANY_TEST=true
    print_header 2 "V1: Running Jest with coverage"

    cd /coverage_reloaded/repo/packages/vuetify

    NODE_ENV=test npx jest --coverage --coverageReporters=lcov --no-cache 2>&1

    cd /coverage_reloaded/repo

    bash /coverage_reloaded/find-and-move-lcov.sh "jest" "true" || COVERAGE_FAILURE=true
fi

# ── 2. V2: Vitest (later pnpm era) ───────────────────────────────────────
# test = vitest. Run vitest with --coverage and explicitly request lcov
# output. Vitest's default coverage reporters are text+html, not lcov,
# so we must specify --coverage.reporter=lcov explicitly.

if [ "$IS_V2" = "true" ]; then
    RAN_ANY_TEST=true
    print_header 2 "V2: Running Vitest with coverage"

    cd /coverage_reloaded/repo/packages/vuetify

    if $IS_PNPM_MAIN_PM; then
        pnpm exec vitest --coverage --coverage.reporter=lcov 2>&1
    else
        npx vitest --coverage --coverage.reporter=lcov 2>&1
    fi

    cd /coverage_reloaded/repo

    bash /coverage_reloaded/find-and-move-lcov.sh "vitest" "true" || COVERAGE_FAILURE=true
fi

# ── 3. Cypress (if cy:run script exists in package.json) ─────────────────
# Vuetify used Cypress for component tests in the mid-era (2021-2024).
# Coverage patches have been applied above to enable @cypress/code-coverage.
#
# Detection reads the cy:run script from packages/vuetify/package.json.
# This is the canonical indicator that Cypress tests are expected to run
# at this commit, and it gives us the exact command to use.
# The command evolved over time:
#   cypress run-ct  →  percy exec -- cypress run --component

print_header 2 "Checking for Cypress tests"

CYPRESS_CMD=""
CYPRESS_WORK_DIR="."
# Check packages/vuetify first (component tests, mid/late era)
# Use absolute paths since we may be in a subdirectory at this point
if [ -f "/coverage_reloaded/repo/packages/vuetify/package.json" ]; then
    CYPRESS_CMD=$(node -p "const p=require('/coverage_reloaded/repo/packages/vuetify/package.json'); (p.scripts&&p.scripts['cy:run'])||(p.scripts&&p.scripts['cypress:run'])||''" 2>/dev/null || echo "")
fi
if [ -n "$CYPRESS_CMD" ]; then
    CYPRESS_WORK_DIR="packages/vuetify"
fi
# Fall back to root package.json (e.g. if cypress:run is defined at root level)
if [ -z "$CYPRESS_CMD" ] && [ -f "/coverage_reloaded/repo/package.json" ]; then
    CYPRESS_CMD=$(node -p "const p=require('/coverage_reloaded/repo/package.json'); (p.scripts&&p.scripts['cy:run'])||(p.scripts&&p.scripts['cypress:run'])||''" 2>/dev/null || echo "")
fi

if [ -n "$CYPRESS_CMD" ]; then
    RAN_ANY_TEST=true

    print_header 3 "  Found cy:run: $CYPRESS_CMD  (in $CYPRESS_WORK_DIR)"


    cd /coverage_reloaded/repo/"$CYPRESS_WORK_DIR"

    # Strip percy exec -- prefix (not available in our environment)
    CYPRESS_CMD_CLEAN="${CYPRESS_CMD#percy exec -- }"
    # Strip --bail (stops at first failure → incomplete coverage)
    CYPRESS_CMD_CLEAN="${CYPRESS_CMD_CLEAN/--bail/}"
    # Strip --headed (not needed in container)
    CYPRESS_CMD_CLEAN="${CYPRESS_CMD_CLEAN/--headed/}"
    CYPRESS_CMD_CLEAN="$(echo "$CYPRESS_CMD_CLEAN" | tr -s ' ')"

    print_header 3 "  Running: xvfb-run npx $CYPRESS_CMD_CLEAN"

    set +e
    xvfb-run --auto-servernum npx $CYPRESS_CMD_CLEAN
    CYPRESS_EXIT=$?
    set -e

    print_header 3 "  Cypress exit code: $CYPRESS_EXIT"

    # Collect coverage — Cypress with @cypress/code-coverage outputs
    # to .nyc_output/out.json; convert to lcov via nyc.
    cd /coverage_reloaded/repo
    if [ -f ".nyc_output/out.json" ]; then
        print_header 3 "  Converting Cypress coverage to lcov format"
        npx nyc report --reporter=lcovonly --report-dir=coverage/cypress 2>&1 || true
    fi
    if [ -f "packages/vuetify/.nyc_output/out.json" ]; then
        print_header 3 "  Converting Cypress coverage (packages/vuetify) to lcov format"
        (cd packages/vuetify && npx nyc report --reporter=lcovonly --report-dir=coverage/cypress 2>&1) || true
    fi

    bash /coverage_reloaded/find-and-move-lcov.sh "cypress" "true" || COVERAGE_FAILURE=true

    cd packages/vuetify
else
    print_header 3 "  No cy:run script found — skipping Cypress tests"
fi

# ── 4. Determine final exit code ──────────────────────────────────────────
# If we ran any test runner but none produced coverage, that's an error.
# If no test infrastructure was found at all, that's also an error.
if [ "$RAN_ANY_TEST" = true ] && [ "$COVERAGE_FAILURE" = true ]; then
    echo "ERROR: One or more test runners executed but produced no coverage files."
    GLOBAL_TEST_EXIT=1
elif [ "$RAN_ANY_TEST" = false ]; then
    echo "ERROR: No test infrastructure detected (no V1/V2 runner, no cy:run script)"
    echo "       Cannot collect coverage for this commit."
    GLOBAL_TEST_EXIT=1
else
    GLOBAL_TEST_EXIT=0
fi

set -e
