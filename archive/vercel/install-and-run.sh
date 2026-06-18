#!/bin/bash
set -e

. /coverage_reloaded/logging.sh
cd /coverage_reloaded/repo

# ── Detect PM ────────────────────────────────────────────────
print_header 2 "Detecting package manager"
if [ "$IS_YARN_MAIN_PM" = "true" ]; then
    PM="yarn"
    INSTALL_CMD="yarn install --frozen-lockfile"
elif [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    PM="pnpm"
    INSTALL_CMD="pnpm install --no-frozen-lockfile"
elif [ "$IS_NPM_MAIN_PM" = "true" ]; then
    PM="npm"
    INSTALL_CMD="npm install"
else
    echo "ERROR: No known package manager detected" >&2
    exit 1
fi
print_header 3 "Package manager: $PM"

# Set npx registry globally so all npx invocations use WayPack
export npm_config_registry="$WAYPACK_NPM_REGISTRY"

# ── Install dependencies ──────────────────────────────────────
print_header 2 "Installing dependencies"
export NODE_ENV=development
export CI=true

# Handle yarn-specific issues
if [ "$IS_YARN_MAIN_PM" = "true" ]; then
    export YARN_CHECKSUM_BEHAVIOR=ignore
    # Patch yarn.lock for stale registry entries
    sed -i 's|hugomrdias/concat-stream|max-mapper/concat-stream|g' yarn.lock 2>/dev/null || true
    sed -i 's|BitGo/blake2b-wasm|mafintosh/blake2b-wasm|g' yarn.lock 2>/dev/null || true
fi

$INSTALL_CMD

# ── Detect test infrastructure ────────────────────────────────
print_header 2 "Detecting test infrastructure"

ROOT_TEST_SCRIPT=$(node -p "const s=require('./package.json').scripts||{}; s.test||''")
ROOT_TEST_UNIT_SCRIPT=$(node -p "const s=require('./package.json').scripts||{}; s['test-unit']||''")
ROOT_TEST_E2E_SCRIPT=$(node -p "const s=require('./package.json').scripts||{}; s['test-e2e']||''")

HAS_VITEST_CONFIG=$(test -f vitest.config.mts && echo "true" || echo "false")
HAS_VITEST=$(find . -name 'vitest.config.*' -not -path '*/node_modules/*' | head -1 | grep -q . && echo "true" || echo "false")
HAS_LERNA=$(test -f lerna.json && echo "true" || echo "false")
HAS_TURBO=$(node -p "Object.keys(require('./package.json').devDependencies||{}).includes('turbo')" 2>/dev/null || echo "false")

print_header 3 "Root test script" "$ROOT_TEST_SCRIPT"
print_header 3 "Has vitest config" "$HAS_VITEST_CONFIG"
print_header 3 "Has lerna.json" "$HAS_LERNA"
print_header 3 "Has turbo" "$HAS_TURBO"

# ── Install vitest coverage provider ─────────────────────────
# @vitest/coverage-v8 must be resolvable from each workspace package that runs
# vitest. pnpm's strict isolation means root-level installs and NODE_PATH don't
# work — the package must be wired into each package's own resolution graph.
# `pnpm add -r` installs into every workspace package at once.
print_header 2 "Ensuring vitest coverage provider is installed"
if [ "$HAS_VITEST" = "true" ] && [ "$PM" = "pnpm" ]; then
    print_header 3 "Installing @vitest/coverage-v8 into all workspace packages"
    pnpm add --save-dev @vitest/coverage-v8 -r
fi

# ── Bail stripping ────────────────────────────────────────────
# The project uses --bail (jest) and --fail-fast (ava) pervasively.
# We strip them from all package.json scripts at runtime.
print_header 2 "Stripping bail/fail-fast flags from package.json files"
find packages -name 'package.json' -not -path '*/node_modules/*' 2>/dev/null | while read -r pkg; do
    # Strip --bail from jest invocations
    sed -i 's/ --bail//g' "$pkg"
    sed -i 's/--bail //g' "$pkg"
    # Strip --fail-fast from ava invocations
    sed -i 's/ --fail-fast//g' "$pkg"
    sed -i 's/--fail-fast //g' "$pkg"
    # Strip --serial from ava (not bail but reduces parallelism issues)
    sed -i 's/ --serial//g' "$pkg"
    sed -i 's/--serial //g' "$pkg"
done
# Also strip from root package.json
sed -i 's/ --bail//g' package.json
sed -i 's/--bail //g' package.json
sed -i 's/ --fail-fast//g' package.json
sed -i 's/--fail-fast //g' package.json

# ── Helper: run a test suite with coverage ────────────────────
run_suite() {
    local label="$1"
    local cmd="$2"
    local prepend="$3"

    print_header 2 "Running: $label" "$cmd"
    set +e
    eval "$cmd"
    local exit_code=$?
    set -e
    print_header 3 "Exit code: $exit_code"
    bash ../find-and-move-lcov.sh "$label" "$prepend" "$exit_code"
}

# ── Era detection & execution ─────────────────────────────────
if [ "$HAS_VITEST_CONFIG" = "true" ]; then
    # ── Era 3: Vitest (current) ───────────────────────────────
    print_header 1 "Era: Vitest (pnpm + turbo)"

    # vitest v2 supports dot notation for coverage CLI options:
    #   --coverage.reporter=lcov  (NOT --coverageReporters=lcov, which CAC doesn't understand)
    # We must use --coverage.enabled instead of bare --coverage when using dot notation.
    VITEST_COV_OPTS="--coverage.enabled --coverage.reporter=lcov"

    # Run per-package vitest suites via turbo first so .turbo/runs gets created
    if [ "$HAS_TURBO" = "true" ]; then
        # vitest-run tasks: run all tests in a package via vitest
        run_suite "vitest-run" "npx turbo run vitest-run --concurrency=1 -- $VITEST_COV_OPTS" "true"

        # vitest-unit tasks: unit-only vitest runs
        run_suite "vitest-unit" "npx turbo run vitest-unit --concurrency=1 -- $VITEST_COV_OPTS" "true"
    fi

    # Run root-level test suite (needs .turbo/runs from turbo execution above)
    if [ -n "$ROOT_TEST_SCRIPT" ]; then
        run_suite "root-test" "$PM run test $VITEST_COV_OPTS --reporter=verbose" "false"
    fi

elif [ "$HAS_LERNA" = "true" ]; then
    # ── Era 1: Lerna + Ava + nyc ──────────────────────────────
    print_header 1 "Era: Lerna (yarn + ava + nyc)"

    # lerna run --if-present skips packages without the script.
    # --no-bail is MANDATORY: lerna bails by default.
    # We run the key test scripts that exist across the lerna era.

    run_suite "lerna-test-unit" "npx lerna run test-unit --if-present --no-bail --concurrency=1 -- --coverage --coverageReporters=lcov" "true"

    # Pass --coverage to bare "test" scripts via lerna's `--` passthrough.
    # This ensures jest produces lcov output even if the script lacks --coverage.
    run_suite "lerna-test" "npx lerna run test --if-present --no-bail --concurrency=1 -- --coverage --coverageReporters=lcov" "true"

    run_suite "lerna-test-integration-once" "npx lerna run test-integration-once --if-present --no-bail --concurrency=1 -- --coverage --coverageReporters=lcov" "true"

else
    # ── Era 2: Workspaces + Jest (yarn or pnpm, no lerna, no vitest config) ──
    print_header 1 "Era: Workspaces + Jest"

    # Run root-level test if it exists
    if [ -n "$ROOT_TEST_SCRIPT" ] && [ "$ROOT_TEST_SCRIPT" != "exit 0" ]; then
        run_suite "root-test" "$PM test -- --coverage --coverageReporters=lcov" "false"
    fi

    # Run per-package tests via turbo if available
    if [ "$HAS_TURBO" = "true" ]; then
        # turbo run skips packages without the script by default (no --if-present needed)
        run_suite "turbo-test-unit" "npx turbo run test-unit --concurrency=1 -- --coverage --coverageReporters=lcov" "true"

        run_suite "turbo-vitest-unit" "npx turbo run vitest-unit --concurrency=1 -- --coverage --coverageReporters=lcov" "true"
    else
        # No turbo — iterate packages manually
        for pkg_dir in packages/*/; do
            pkg_name=$(basename "$pkg_dir")
            pkg_json="$pkg_dir/package.json"
            if [ ! -f "$pkg_json" ]; then continue; fi

            test_unit=$(node -p "const s=require('./$pkg_json').scripts||{}; s['test-unit']||''" 2>/dev/null)

            if [ -n "$test_unit" ]; then
                print_header 3 "Package: $pkg_name — test-unit"
                (cd "$pkg_dir" && run_suite "${pkg_name}-unit" "$PM run test-unit -- --coverage --coverageReporters=lcov" "true")
            fi
        done
    fi
fi

print_header 1 "Coverage collection complete"
