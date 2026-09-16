#!/bin/bash
set -e

unset NPM_CONFIG_LOCATION

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit"
    exit 2
fi

if [ "$IS_YARN_MAIN_PM" != "true" ]; then
    print_header 2 "ERROR: unsupported package manager" "uploader uses yarn for every commit in the study window, but this commit resolved to '$package_manager'"
    exit 1
fi

TEST_SCRIPT=$(node -p "((require('./package.json').scripts||{}).test) || ''")
if [ -z "$TEST_SCRIPT" ]; then
    print_header 2 "NOT APPLICABLE" "No test script at this commit"
    exit 2
fi

print_header 4 "test script: $TEST_SCRIPT"

print_header 2 "Installing dependencies"

if [ -f yarn.lock ]; then
    CHROMEDRIVER_VERSION=$(awk '/^"?electron-chromedriver@/{f=1;next} f&&/version/{gsub(/[" ]/,"",$2); print $2; exit}' yarn.lock)
fi
if [ -n "${CHROMEDRIVER_VERSION:-}" ]; then
    print_header 2 "Pre-seeding electron-chromedriver cache" "version $CHROMEDRIVER_VERSION"
    export ELECTRON_CACHE="$HOME/.cache/electron"
    mkdir -p "$ELECTRON_CACHE"
    curl -fsSL "http://waypack:3000/request/https://github.com/electron/electron/releases/download/v${CHROMEDRIVER_VERSION}/chromedriver-v${CHROMEDRIVER_VERSION}-linux-x64.zip" \
        -o "$ELECTRON_CACHE/chromedriver-v${CHROMEDRIVER_VERSION}-linux-x64.zip"
    curl -fsSL "http://waypack:3000/request/https://github.com/electron/electron/releases/download/v${CHROMEDRIVER_VERSION}/SHASUMS256.txt" \
        -o "$ELECTRON_CACHE/SHASUMS256.txt-${CHROMEDRIVER_VERSION}"
fi

export ELECTRON_MIRROR="http://waypack:3000/request/https://github.com/electron/electron/releases/download/"

YARN_MAJOR=$(yarn --version | cut -d. -f1)
if [ "$YARN_MAJOR" = "1" ]; then
    yarn install --ignore-engines
else
    export YARN_ENABLE_IMMUTABLE_INSTALLS=false
    yarn install
fi

ELECTRON_CLI="node_modules/electron/cli.js"
if [ -f "$ELECTRON_CLI" ] && ! grep -q -- '--no-sandbox' "$ELECTRON_CLI"; then
    print_header 4 "NOTICE: Patching electron cli.js to pass --no-sandbox"
    sed -i "s|process.argv.slice(2)|['--no-sandbox'].concat(process.argv.slice(2))|" "$ELECTRON_CLI"
fi

print_header 2 "Starting Xvfb"
Xvfb :99 -screen 0 1280x1024x24 &
export DISPLAY=:99
export ELECTRON_OPTIONS="--no-sandbox"
sleep 2

# The Tandem driver used to live in this repo, but was made private on
# 2022-06-22 (34e707f87 "make Tandem drivers private", then e98a41a6f "add
# Tandem driver as private submodule"). Its source is only present in the
# superproject tree while it is checked in; once lib/drivers/tandem is a
# submodule gitlink (160000) the source is not part of the commit and our
# checkout never materialises it (the repo is private, see
# tidepool-org/uploader#1698). test/lib/tandem/testTandemSimulator.js then
# fails to resolve its require and the whole suite errors out.
# The suite only exercises that external driver, so exclude it exactly when the
# driver is not part of the commit. Probing the commit tree (not a date) keeps
# this commit-accurate: pre-2022 commits still run the suite.
TANDEM_SIMULATOR="lib/drivers/tandem/tandemSimulator.js"
TANDEM_TEST="test/lib/tandem/testTandemSimulator.js"
TANDEM_EXCLUDE_ARGS=()
if ! git rev-parse --verify --quiet "${revision:-HEAD}:${TANDEM_SIMULATOR}" >/dev/null; then
    print_header 4 "NOTICE: excluding tandem suite" "${TANDEM_SIMULATOR} is not part of this commit (private submodule); skipping ${TANDEM_TEST}"
    TANDEM_EXCLUDE_ARGS=(
        --testPathIgnorePatterns "/node_modules/"
        --testPathIgnorePatterns "$TANDEM_TEST"
    )
fi

suite_start "unit" "jest behavioral suite (test/app + test/lib) via the Electron runner"

set +e
yarn test --coverage --coverageReporters=lcov --runInBand "${TANDEM_EXCLUDE_ARGS[@]}"
TEST_EXIT=$?
set -e

bash ../find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"
suite_end "unit" "$TEST_EXIT"

if [ "$TEST_EXIT" -eq 1 ]; then
    print_header 4 "WARNING: tests exited with code 1 — coverage was still collected, see log for failing tests"
elif [ "$TEST_EXIT" -gt 1 ]; then
    print_header 2 "ERROR: test runner exited with code $TEST_EXIT, indicating a setup/runtime problem"
    exit "$TEST_EXIT"
fi

print_header 1 "uploader coverage run complete"
