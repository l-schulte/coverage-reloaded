#!/bin/bash
set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/na-if-focus-marker.sh

cd "$REPOPATH"

if [ ! -f package.json ]; then
    not_applicable "No Babel root package.json at this commit"
fi

if [ "$IS_YARN_MAIN_PM" != "true" ]; then
    print_header 2 "ERROR: unsupported package manager" "Babel uses Yarn, resolved to '$package_manager'"
    exit 1
fi

na_if_focus_marker --runner jest packages codemods eslint

export BABEL_ENV=test
export FORCE_COLOR=true
export BROWSERSLIST_IGNORE_OLD_DATA=true
export BABEL_JEST_WORKERS="${BABEL_JEST_WORKERS:-2}"
export CI=true
export NODE_OPTIONS="--max-old-space-size=8192 --require /coverage_reloaded/browserslist-child-env.cjs${NODE_OPTIONS:+ $NODE_OPTIONS}"

# Prepend yarn-workers-shim to PATH so Makefile.js (which uses shell.which("yarn"))
# and all make targets route through the worker-capped shim.
mkdir -p /tmp/shim-bin
ln -sf /coverage_reloaded/yarn-workers-shim /tmp/shim-bin/yarn
export PATH="/tmp/shim-bin:$PATH"

# Fix upstream race condition in Gulpfile where build-babel and generate-runtime-helpers
# were placed in parallel, causing build-babel to compile @babel/helpers before
# helpers-generated.js was written (leading to 'Unknown helper typeof' in build-dist).
for gf in Gulpfile.mjs Gulpfile.js; do
    if [ -f "$gf" ] && grep -q 'generate-runtime-helpers' "$gf"; then
        sed -i 's/gulp\.parallel("build-rollup", "build-babel", "generate-runtime-helpers")/gulp.series("generate-runtime-helpers", gulp.parallel("build-rollup", "build-babel"))/g' "$gf"
    fi
done

# Raise the hard-coded 5s wall-clock timeout in the babel-cli `--watch` fixture
# executors. Each of those executors waits for the first watch build and prints
# "EXECUTOR TIMEOUT" if it has not landed within 5000ms. Under coverage
# instrumentation (the babel-plugin-istanbul era) and inside a loaded container
# the first build takes far longer, so `bin/babel > dir --out-dir --watch ...`
# fails on timing alone while the rest of the suite passes. Only the wait is
# widened - what the fixture asserts is unchanged.
if [ -d packages/babel-cli/test/fixtures ]; then
    print_header 2 "Widening babel-cli --watch fixture executors" "5000ms -> 120000ms (timing only, assertions unchanged)"
    while IFS= read -r -d '' fx; do
        if grep -q 'EXECUTOR TIMEOUT' "$fx"; then
            echo "  patching $fx"
            sed -i '/EXECUTOR TIMEOUT/,/}, [0-9][0-9]*);/ s/}, [0-9][0-9]*);/}, 120000);/' "$fx"
        fi
    done < <(find packages/babel-cli/test/fixtures -name executor.js -print0)
fi

CAP_DROP=()
if command -v setpriv >/dev/null 2>&1; then
    CAP_DROP=(setpriv --bounding-set=-dac_override,-dac_read_search --inh-caps=-dac_override,-dac_read_search --ambient-caps=-dac_override,-dac_read_search)
fi

if [ ! -f scripts/test-cov.sh ]; then
    # Post-scripts/test-cov.sh era (July 2022 onwards):
    # make test-ci-coverage accidentally dropped --coverage in mid-2022 (#14802).
    # The developer target 'make test-cov' consistently retains coverage (jest --coverage / c8 jest).
    # Bootstrap dependencies first with BABEL_ENV=test so all helpers compile.
    print_header 2 "Installing dependencies and building" "make bootstrap with BABEL_ENV=test BABEL_COVERAGE=true"
    BABEL_ENV=test BABEL_COVERAGE=true make bootstrap

    print_header 2 "Running project coverage target" "make test-cov with yarn-workers-shim"
    suite_start "unit" "Project coverage target over packages, codemods, and eslint"
    set +e
    "${CAP_DROP[@]}" make test-cov
    UNIT_EXIT=$?
    set -e
else
    # Istanbul era: the project's coverage target bootstraps with coverage and
    # runs scripts/test-cov.sh, but its bootstrap skips the standalone bundle
    # while the early Jest config does not ignore the unbuilt standalone tests.
    print_header 2 "Installing dependencies and building" "make bootstrap with BABEL_ENV=test BABEL_COVERAGE=true"
    BABEL_ENV=test BABEL_COVERAGE=true make bootstrap
    print_header 2 "Building standalone bundle" "make build-standalone"
    env -u BABEL_ENV -u BABEL_COVERAGE make build-standalone

    suite_start "unit" "Project Istanbul coverage script over packages, codemods, and eslint"
    set +e
    "${CAP_DROP[@]}" env BABEL_ENV=test TEST_TYPE=cov CI=true ./scripts/test-cov.sh
    UNIT_EXIT=$?
    set -e
fi

bash ../find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
suite_end "unit" "$UNIT_EXIT"
