#!/usr/bin/env bash
set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/resolve-and-pin.sh
source /coverage_reloaded/has-option.sh
source /coverage_reloaded/assert-suite-ran.sh
source /coverage_reloaded/na-if-focus-marker.sh

cd /coverage_reloaded/repo
REPOPATH="$(pwd)"
export NODE_OPTIONS="--require /coverage_reloaded/mock-code-of-conduct.js --no-deprecation ${NODE_OPTIONS:-}"

if [ ! -f package.json ]; then
    not_applicable "No package.json at this commit"
fi

if [ "$IS_YARN_MAIN_PM" != "true" ]; then
    print_header 2 "ERROR: unsupported package manager" "webpack uses yarn every commit in the study window, but this commit resolved to '$package_manager'"
    exit 1
fi

if ! has_script "cover:unit"; then
    not_applicable "No cover:unit script at this commit"
fi

na_if_focus_marker --runner jest test

print_header 2 "Installing dependencies"
yarn install --frozen-lockfile

if [ ! -e node_modules/webpack ]; then
    print_header 2 "Linking webpack into its own node_modules"
    ln -sfn "$REPOPATH" node_modules/webpack
fi

if [ -f test/configCases/ecmaVersion/browserslist/package.json ]; then
    if grep -q '"dynamicImport": false' test/configCases/ecmaVersion/browserslist/webpack.config.js 2>/dev/null; then
        sed -i 's|"maintained node versions"|"node 10", "node 12", "node 14"|' \
            test/configCases/ecmaVersion/browserslist/package.json
    elif grep -q "nodeBuiltinModuleGetter" test/configCases/ecmaVersion/browserslist/webpack.config.js 2>/dev/null; then
        sed -i 's|"maintained node versions"|"node 20", "node 22", "node 24"|' \
            test/configCases/ecmaVersion/browserslist/package.json
    else
        sed -i 's|"maintained node versions"|"node 14", "node 16"|' \
            test/configCases/ecmaVersion/browserslist/package.json
    fi
fi
if [ -f test/configCases/ecmaVersion/browserslist-query-with-config-file/webpack.config.js ]; then
    sed -i 's|browserslist:maintained node versions|browserslist:node 18, node 20|' \
        test/configCases/ecmaVersion/browserslist-query-with-config-file/webpack.config.js
fi
if [ -f test/configCases/ecmaVersion/browserslist-options/browserslist-query-with-config-file.config.js ]; then
    sed -i 's|browserslist:maintained node versions|browserslist:node 18, node 20|' \
        test/configCases/ecmaVersion/browserslist-options/browserslist-query-with-config-file.config.js
fi

BROWSER_SUITES=(
    "--testPathIgnorePatterns=ProfilingPlugin.unittest"
    "--testPathIgnorePatterns=WebpackDevServer.longtest"
)

run_jest_coverage_suite() {
    local suite="$1"
    local script="$2"
    local log="$REPOPATH/.suite-${suite}.log"

    suite_start "$suite" "yarn $script (jest --coverage)"

    set +e
    yarn "$script" \
        --coverageReporters=lcov \
        --ci \
        --maxWorkers=2 \
        "${BROWSER_SUITES[@]}" 2>&1 | tee "$log"
    local exit_code=${PIPESTATUS[0]}
    set -e

    assert_suite_ran "$suite" "jest" "$log" "$exit_code"
    bash /coverage_reloaded/find-and-move-lcov.sh "$suite" "false" "$exit_code"
    suite_end "$suite" "$exit_code"
}

run_jest_coverage_suite "unit" "cover:unit"

if has_script "cover:integration:a" && has_script "cover:integration:b"; then
    run_jest_coverage_suite "integration-a" "cover:integration:a"
    run_jest_coverage_suite "integration-b" "cover:integration:b"
else
    run_jest_coverage_suite "integration" "cover:integration"
fi

print_header 1 "webpack coverage run complete"
