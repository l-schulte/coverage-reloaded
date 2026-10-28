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
export NODE_OPTIONS="--require /coverage_reloaded/browserslist-child-env.cjs${NODE_OPTIONS:+ $NODE_OPTIONS}"

CAP_DROP=()
if command -v setpriv >/dev/null 2>&1; then
    CAP_DROP=(setpriv --bounding-set=-dac_override,-dac_read_search --inh-caps=-dac_override,-dac_read_search --ambient-caps=-dac_override,-dac_read_search)
fi

if [ ! -f scripts/test-cov.sh ]; then
    # c8 era: the project's own coverage target owns bootstrap and the c8 run.
    print_header 2 "Running project coverage target" "make test-ci-coverage with yarn-workers-shim"
    suite_start "unit" "Project c8 coverage target over packages, codemods, and eslint"
    set +e
    "${CAP_DROP[@]}" make test-ci-coverage YARN=/coverage_reloaded/yarn-workers-shim
    UNIT_EXIT=$?
    set -e
else
    # Istanbul era: the project's coverage target bootstraps with coverage and
    # runs scripts/test-cov.sh, but its bootstrap skips the standalone bundle
    # while the early Jest config does not ignore the unbuilt standalone tests.
    print_header 2 "Installing dependencies and building" "make bootstrap with BABEL_COVERAGE=true"
    BABEL_COVERAGE=true make bootstrap
    print_header 2 "Building standalone bundle" "make build-standalone"
    env -u BABEL_ENV -u BABEL_COVERAGE make build-standalone

    suite_start "unit" "Project Istanbul coverage script over packages, codemods, and eslint"
    set +e
    "${CAP_DROP[@]}" env BABEL_ENV=test TEST_TYPE=cov ./scripts/test-cov.sh
    UNIT_EXIT=$?
    set -e
fi

bash ../find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
suite_end "unit" "$UNIT_EXIT"
