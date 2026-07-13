#!/usr/bin/env bash
set -euo pipefail

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo
REPO_ROOT="$(pwd)"
COVERAGE_DIR="$REPO_ROOT/coverage"

# =============================================================================
# 1. PACKAGE MANAGER DETECTION
# =============================================================================
if $IS_YARN_MAIN_PM; then
    PM_EXEC="yarn"
    PM_INSTALL="yarn install --frozen-lockfile"
    echo "Package manager: yarn"
elif $IS_PNPM_MAIN_PM; then
    PM_EXEC="pnpm"
    PM_INSTALL="pnpm install --frozen-lockfile"
    echo "Package manager: pnpm"
else
    echo "ERROR: No supported package manager detected (IS_YARN_MAIN_PM=$IS_YARN_MAIN_PM, IS_PNPM_MAIN_PM=$IS_PNPM_MAIN_PM)"
    exit 1
fi

# =============================================================================
# 2. DEPENDENCY INSTALLATION
# =============================================================================
print_header 2 "Installing dependencies..."
$PM_INSTALL

# =============================================================================
# 2b. FIX: test-exclude@6 + minimatch@9 incompatibility
# =============================================================================
# When the root package.json forces minimatch to ^9.0.2 (for glob@10.x etc.),
# test-exclude@6.0.0 (from babel-plugin-istanbul) breaks because it does
# `const minimatch = require('minimatch')` expecting the function directly
# (minimatch@3 behavior), but minimatch@9 exports an object instead.
#
# The project developers never hit this: their "test" script is "jest --color"
# (no --coverage flag), so babel-plugin-istanbul / test-exclude is never loaded.
# We add --coverage in run_native_command(), which activates the instrumentation
# chain and surfaces the incompatibility.
#
# Fix: patch the import in the installed test-exclude to handle both minimatch
# versions. This keeps test-exclude@6.0.0 (timeline-accurate) while making it
# compatible with minimatch@9. The typeof check is a no-op for minimatch@3.
#
# Why not upgrade test-exclude to 7.x (which supports minimatch@9)?
# WayPack only serves versions that existed at the commit's timestamp.
# test-exclude@7.0.0 was released 2024-06-10, after the affected commits.
#
# Why not downgrade minimatch back to 3.x?
# The resolution exists because other packages (e.g. glob@10.x) need minimatch@9.
# Removing or downgrading it would break those dependencies.
NEEDS_TEST_EXCLUDE_PATCH=false

# Check 1: minimatch resolution forces ^9.x
if node -e "
  const fs = require('fs');
  const pkg = JSON.parse(fs.readFileSync('package.json','utf8'));
  const mm = (pkg.resolutions || {}).minimatch || '';
  process.exit(mm.includes('^9.') ? 0 : 1);
" 2>/dev/null; then
    # Check 2: test-exclude is at 6.x (constrains minimatch to ^3)
    TEST_EXCLUDE_VER=""
    if [ -f node_modules/test-exclude/package.json ]; then
        TEST_EXCLUDE_VER="$(node -p "require('./node_modules/test-exclude/package.json').version" 2>/dev/null)"
    fi
    if [[ "$TEST_EXCLUDE_VER" == 6.* ]]; then
        NEEDS_TEST_EXCLUDE_PATCH=true
    fi
fi

if [ "$NEEDS_TEST_EXCLUDE_PATCH" = true ]; then
    print_header 2 "Patching test-exclude@${TEST_EXCLUDE_VER} for minimatch@9 compatibility"
    find node_modules -path '*/test-exclude/index.js' -exec sed -i \
      "s|const minimatch = require('minimatch');|const minimatch = (m => typeof m === 'function' ? m : m.minimatch)(require('minimatch'));|" {} +
fi

# =============================================================================
# 3. INSTALL VITEST COVERAGE PROVIDER
# =============================================================================
print_header 3 "Installing @vitest/coverage-istanbul if vitest is present"
if node -e "require.resolve('vitest/package.json')" >/dev/null 2>&1; then
    VITEST_VERSION="$(node -p "require('vitest/package.json').version")"
    print_header 4 "Vitest detected (version $VITEST_VERSION)"

    if $IS_YARN_MAIN_PM; then
        yarn add --dev -W "@vitest/coverage-istanbul@$VITEST_VERSION"
    elif $IS_PNPM_MAIN_PM; then
        pnpm add -D -w "@vitest/coverage-istanbul@$VITEST_VERSION"
    fi
else
    print_header 4 "Vitest not installed in this commit. Skipping provider install."
fi
# =============================================================================
# 4. LERNA BOOTSTRAP (if lerna is used)
# =============================================================================
if [ -f lerna.json ]; then
    print_header 3 "lerna.json detected. Bootstrapping and building with lerna..."
    npx --registry="$WAYPACK_NPM_REGISTRY" lerna bootstrap
    npx --registry="$WAYPACK_NPM_REGISTRY" lerna run build --no-bail
fi

# =============================================================================
# 5. PATCH: SKIP LIVE API CACHING IN BUILD
# =============================================================================
# The build script (scripts/build.js) fetches fresh data from the live Linode API
# and overwrites src/cachedData/*.json before compiling. The live API may return
# fields not yet in the TypeScript types at older commits, causing build failures.
# The committed cached data already matches the types, so we replace the fetcher
# with a no-op.
BUILD_REQUESTS="packages/manager/scripts/buildRequests.js"
if [ -f "$BUILD_REQUESTS" ]; then
    print_header 3 "Patching buildRequests.js to skip live API caching"
    cp /coverage_reloaded/buildRequests.noop.js "$BUILD_REQUESTS"
fi

# =============================================================================
# 6. ROOT BUILD
# =============================================================================
print_header 2 "Running root build (if applicable)"

BUILD_SCRIPT=$(node -p "require('./package.json').scripts['build'] || ''")
if [ -n "$BUILD_SCRIPT" ] && [ ! -f lerna.json ]; then
    echo "Build script found. Patching webpack size limits and building..."
    WEBPACK_CONFIG="packages/manager/config/webpack.config.prod.js"
    if [ -f "$WEBPACK_CONFIG" ]; then
        sed -i 's/maxEntrypointSize: 1180000/maxEntrypointSize: 3000000/g' "$WEBPACK_CONFIG"
        sed -i 's/maxAssetSize: 1180000/maxAssetSize: 3000000/g' "$WEBPACK_CONFIG"
    fi
    $PM_EXEC run build
elif [ -n "$BUILD_SCRIPT" ] && [ -f lerna.json ]; then
    echo "Build already handled by lerna above. Skipping."
else
    echo "No build script found. Skipping build step."
fi

# =============================================================================
# 7. SUB-PACKAGE BUILD
# =============================================================================
SDK_BUILD_SCRIPT=$(node -p "require('./package.json').scripts['build:sdk'] || ''")
VALIDATION_BUILD_SCRIPT=$(node -p "require('./package.json').scripts['build:validation'] || ''")

if [ -n "$SDK_BUILD_SCRIPT" ] && [ ! -f lerna.json ]; then
    echo "Building SDK..."
    $PM_EXEC run build:sdk
fi

if [ -n "$VALIDATION_BUILD_SCRIPT" ] && [ ! -f lerna.json ]; then
    echo "Building validation package..."
    $PM_EXEC run build:validation
fi

# =============================================================================
# 8. HELPERS
# =============================================================================
print_header 2 "Defining helper functions"

has_script() {
    node -e "const p=require('./package.json'); process.exit((p.scripts && p.scripts['$1']) ? 0 : 1)"
}

get_root_script() {
    node -p "((require('./package.json').scripts || {})['$1']) || ''"
}

get_pkg_script() {
    local pkg_json="$1"
    local script_name="$2"
    node -p "((require('./${pkg_json}').scripts || {})['${script_name}']) || ''"
}

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

find_pkg_dir_by_name() {
    local want="$1"
    node - "$want" <<'NODE'
const fs = require('fs');
const path = require('path');

const want = process.argv[2];
const roots = ['packages'];

function walk(dir) {
  if (!fs.existsSync(dir)) return null;
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      if (ent.name === 'node_modules' || ent.name === '.git' || ent.name === 'coverage') continue;
      const found = walk(p);
      if (found) return found;
    } else if (ent.name === 'package.json') {
      try {
        const j = JSON.parse(fs.readFileSync(p, 'utf8'));
        if (j.name === want) {
          process.stdout.write(path.dirname(p));
          process.exit(0);
        }
      } catch {}
    }
  }
  return null;
}

for (const root of roots) {
  const found = walk(root);
  if (found) {
    process.stdout.write(found);
    process.exit(0);
  }
}
process.exit(1);
NODE
}

normalize_cmd() {
    local cmd
    cmd="$(trim "$1")"

    case "$cmd" in
        yarn\ vitest\ * ) echo "${cmd#yarn }" ;;
        pnpm\ vitest\ * ) echo "${cmd#pnpm }" ;;
        yarn\ jest\ * ) echo "${cmd#yarn }" ;;
        pnpm\ jest\ * ) echo "${cmd#pnpm }" ;;
        yarn\ npx\ * ) echo "${cmd#yarn }" ;;
        pnpm\ npx\ * ) echo "${cmd#pnpm }" ;;
        * ) echo "$cmd" ;;
    esac
}

classify_runner() {
    local cmd="$1"
    if echo "$cmd" | grep -Eiq '(^|[[:space:]])vitest([[:space:]]|$)'; then
        echo "vitest"
    elif echo "$cmd" | grep -Eiq '(^|[[:space:]])(jest|npx[[:space:]]+jest)([[:space:]]|$)'; then
        echo "jest"
    elif echo "$cmd" | grep -Eiq 'node[[:space:]].*scripts/test\.js([[:space:]]|$)'; then
        echo "jest-wrapper"
    else
        echo "unknown"
    fi
}

ROOT_TARGET_KIND=""
ROOT_TARGET_PKG=""
ROOT_TARGET_EXTRA=""
ROOT_TARGET_CMD=""

resolve_root_target() {
    local script_name="$1"
    local root_cmd
    root_cmd="$(trim "$(get_root_script "$script_name")")"

    ROOT_TARGET_KIND=""
    ROOT_TARGET_PKG=""
    ROOT_TARGET_EXTRA=""
    ROOT_TARGET_CMD=""

    if [ -z "$root_cmd" ]; then
        echo "ERROR: Root script '$script_name' is empty or missing."
        return 1
    fi

    if echo "$root_cmd" | grep -Eq '^yarn[[:space:]]+workspace[[:space:]]+[^[:space:]]+[[:space:]]+test([[:space:]].*)?$'; then
        ROOT_TARGET_KIND="workspace"
        ROOT_TARGET_PKG="$(echo "$root_cmd" | sed -E 's/^yarn[[:space:]]+workspace[[:space:]]+([^[:space:]]+)[[:space:]]+test([[:space:]].*)?$/\1/')"
        ROOT_TARGET_EXTRA="$(echo "$root_cmd" | sed -nE 's/^yarn[[:space:]]+workspace[[:space:]]+[^[:space:]]+[[:space:]]+test(.*)$/\1/p')"
        ROOT_TARGET_EXTRA="$(trim "$ROOT_TARGET_EXTRA")"
        return 0
    fi

    if echo "$root_cmd" | grep -Eq '^pnpm[[:space:]]+run[[:space:]]+--filter[[:space:]]+[^[:space:]]+[[:space:]]+test([[:space:]].*)?$'; then
        ROOT_TARGET_KIND="workspace"
        ROOT_TARGET_PKG="$(echo "$root_cmd" | sed -E 's/^pnpm[[:space:]]+run[[:space:]]+--filter[[:space:]]+([^[:space:]]+)[[:space:]]+test([[:space:]].*)?$/\1/')"
        ROOT_TARGET_EXTRA="$(echo "$root_cmd" | sed -nE 's/^pnpm[[:space:]]+run[[:space:]]+--filter[[:space:]]+[^[:space:]]+[[:space:]]+test(.*)$/\1/p')"
        ROOT_TARGET_EXTRA="$(trim "$ROOT_TARGET_EXTRA")"
        return 0
    fi

    if echo "$root_cmd" | grep -Eq '^lerna[[:space:]]+run[[:space:]]+test([[:space:]].*)?$'; then
        ROOT_TARGET_KIND="workspace"

        if echo "$root_cmd" | grep -Eq -- '--scope='; then
            ROOT_TARGET_PKG="$(echo "$root_cmd" | sed -E 's/.*--scope=([^[:space:]]+).*/\1/')"
        elif echo "$root_cmd" | grep -Eq -- '--scope[[:space:]]+[^[:space:]]+'; then
            ROOT_TARGET_PKG="$(echo "$root_cmd" | sed -E 's/.*--scope[[:space:]]+([^[:space:]]+).*/\1/')"
        else
            echo "ERROR: Could not resolve --scope from lerna command: $root_cmd"
            return 1
        fi

        if [[ "$root_cmd" == *" -- "* ]]; then
            ROOT_TARGET_EXTRA="${root_cmd#* -- }"
            ROOT_TARGET_EXTRA="$(trim "$ROOT_TARGET_EXTRA")"
        else
            ROOT_TARGET_EXTRA=""
        fi
        return 0
    fi

    ROOT_TARGET_KIND="root"
    ROOT_TARGET_CMD="$root_cmd"
    return 0
}

find_runner_bin() {
    local runner="$1"
    local cwd="$2"

    local candidates=(
        "$cwd/node_modules/.bin/$runner"
        "$REPO_ROOT/node_modules/.bin/$runner"
        "$(dirname "$cwd")/node_modules/.bin/$runner"
        "$(dirname "$(dirname "$cwd")")/node_modules/.bin/$runner"
    )

    for p in "${candidates[@]}"; do
        if [ -x "$p" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    done

    return 1
}

run_native_command() {
    local label="$1"
    local cwd="$2"
    local base_cmd="$3"
    local passthrough="${4:-}"

    local runner
    local full_cmd
    local exit_code
    local runner_bin

    base_cmd="$(normalize_cmd "$base_cmd")"
    runner="$(classify_runner "$base_cmd")"

    if [ "$runner" = "unknown" ]; then
        echo "ERROR: Unclassified test command for '$label': $base_cmd" >&2
        return 1
    fi

    case "$runner" in
        jest)
            runner_bin="$(find_runner_bin "jest" "$cwd")" || {
                echo "ERROR: Could not locate executable for runner 'jest' from $cwd" >&2
                return 1
            }
            base_cmd="$(echo "$base_cmd" | sed -E "s#^(npx[[:space:]]+)?jest([[:space:]]|$)#${runner_bin//\//\\/}\2#")"
            ;;
        vitest)
            runner_bin="$(find_runner_bin "vitest" "$cwd")" || {
                echo "ERROR: Could not locate executable for runner 'vitest' from $cwd" >&2
                return 1
            }
            base_cmd="$(echo "$base_cmd" | sed -E "s#^(yarn[[:space:]]+)?vitest([[:space:]]|$)#${runner_bin//\//\\/}\2#")"
            ;;
        jest-wrapper)
            ;;
    esac

    rm -rf "$COVERAGE_DIR"

    case "$runner" in
        vitest)
            full_cmd="$base_cmd"
            [ -n "$passthrough" ] && full_cmd="$full_cmd $passthrough"
            full_cmd="$full_cmd --run --coverage.enabled --coverage.reporter=lcov --coverage.provider=istanbul --coverage.reportsDirectory=$COVERAGE_DIR --coverage.reportOnFailure --bail=0"
            suite_start "$label" "Running $label (vitest native coverage)"
            ;;
        jest|jest-wrapper)
            full_cmd="$base_cmd"
            [ -n "$passthrough" ] && full_cmd="$full_cmd $passthrough"
            full_cmd="$full_cmd --coverage --coverageReporters=lcov --coverageDirectory=$COVERAGE_DIR --watchAll=false --bail=0"
            suite_start "$label" "Running $label (jest native coverage)"
            ;;
    esac

    set +e
    (
        cd "$cwd"
        export CI=true
        export NODE_OPTIONS="--max-old-space-size=8192"
        bash -lc "$full_cmd"
    )
    exit_code=$?
    set -e

    bash ../find-and-move-lcov.sh "$label" "false" "$exit_code"
    suite_end "$label" "$exit_code"
    return "$exit_code"
}

run_resolved_suite() {
    local label="$1"
    local script_name="$2"
    local pkg_dir
    local pkg_cmd

    print_header 4 "Trying to run $label"

    resolve_root_target "$script_name"

    if [ "$ROOT_TARGET_KIND" = "root" ]; then
        run_native_command "$label" "$REPO_ROOT" "$ROOT_TARGET_CMD" ""
        return $?
    fi

    pkg_dir="$(find_pkg_dir_by_name "$ROOT_TARGET_PKG")" || {
        echo "ERROR: Could not find package directory for workspace '$ROOT_TARGET_PKG'" >&2
        return 1
    }

    pkg_cmd="$(trim "$(get_pkg_script "$pkg_dir/package.json" "test")")"
    if [ -z "$pkg_cmd" ]; then
        echo "ERROR: Workspace '$ROOT_TARGET_PKG' has no test script in $pkg_dir/package.json" >&2
        return 1
    fi

    run_native_command "$label" "$REPO_ROOT/$pkg_dir" "$pkg_cmd" "$ROOT_TARGET_EXTRA"
    return $?
}

# run_project_coverage_script() {
#     local exit_code

#     rm -rf "$COVERAGE_DIR"

#     suite_start "coverage" "Running coverage (project-owned script)"
#     set +e
#     export NODE_OPTIONS="--max-old-space-size=8192"
#     export CI=true
#     $PM_EXEC run coverage
#     exit_code=$?
#     set -e

#     bash ../find-and-move-lcov.sh "coverage" "false" "$exit_code"
#     suite_end "coverage" "$exit_code"
#     return "$exit_code"
# }

run_suite_allow_test_fail() {
    local rc

    if "$@"; then
        return 0
    else
        rc=$?
        if [ "$rc" -eq 1 ]; then
            return 0
        fi
        return "$rc"
    fi
}

# =============================================================================
# 9. RUN TEST SUITES
# =============================================================================
print_header 2 "Running tests"

HAS_ANY_SUITE=false

if has_script "test:manager"; then
    HAS_ANY_SUITE=true
    run_suite_allow_test_fail run_resolved_suite "test:manager" "test:manager"
else
    print_header 3 "No test:manager script found in package.json. Skipping."
fi

if has_script "test:sdk"; then
    HAS_ANY_SUITE=true
    run_suite_allow_test_fail run_resolved_suite "test:sdk" "test:sdk"
else
    print_header 3 "No test:sdk script found in package.json. Skipping."
fi

if has_script "test:ui"; then
    HAS_ANY_SUITE=true
    run_suite_allow_test_fail run_resolved_suite "test:ui" "test:ui"
else
    print_header 3 "No test:ui script found in package.json. Skipping."
fi

if has_script "test:search"; then
    HAS_ANY_SUITE=true
    run_suite_allow_test_fail run_resolved_suite "test:search" "test:search"
else
    print_header 3 "No test:search script found in package.json. Skipping."
fi

if has_script "test:validation"; then
    HAS_ANY_SUITE=true
    run_suite_allow_test_fail run_resolved_suite "test:validation" "test:validation"
else
    print_header 3 "No test:validation script found in package.json. Skipping."
fi

if has_script "test:utilities"; then
    HAS_ANY_SUITE=true
    run_suite_allow_test_fail run_resolved_suite "test:utilities" "test:utilities"
else
    print_header 3 "No test:utilities script found in package.json. Skipping."
fi

if has_script "test:queries"; then
    HAS_ANY_SUITE=true
    run_suite_allow_test_fail run_resolved_suite "test:queries" "test:queries"
else
    print_header 3 "No test:queries script found in package.json. Skipping."
fi

if has_script "test:shared"; then
    HAS_ANY_SUITE=true
    run_suite_allow_test_fail run_resolved_suite "test:shared" "test:shared"
else
    print_header 3 "No test:shared script found in package.json. Skipping."
fi

# Runs the same tests as the "test" script, but with coverage enabled. 
# However, it does not generate lcov by default and instead tries to open
# the coverage report in a browser. We just run the "test" script instead.
# if [ "$HAS_ANY_SUITE" = false ] && has_script "coverage"; then
#     HAS_ANY_SUITE=true
#     run_suite_allow_test_fail run_project_coverage_script
# fi

if [ "$HAS_ANY_SUITE" = false ] && has_script "test"; then
    HAS_ANY_SUITE=true
    run_suite_allow_test_fail run_resolved_suite "unit" "test"
fi

if [ "$HAS_ANY_SUITE" = false ]; then
    echo "ERROR: No test or coverage script found in package.json."
    exit 1
fi

# =============================================================================
# 10. EXIT
# =============================================================================
exit 0