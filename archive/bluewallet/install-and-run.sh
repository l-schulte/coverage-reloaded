#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh
source /coverage_reloaded/patch-git-deps.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

print_header 2 "Patching broken GitHub dependency URLs"

# BlueWallet/react-native-document-picker → react-native-documents/document-picker
patch_git_dep_simple "react-native-document-picker" \
    "BlueWallet/react-native-document-picker" \
    "react-native-documents/document-picker"

# BlueWallet/react-native-qrcode-local-image → @remobile/react-native-qrcode-local-image ^1.0.4
patch_git_dep_json "@remobile/react-native-qrcode-local-image" \
    "BlueWallet/react-native-qrcode-local-image" \
    "^1.0.4"
if [ -f package-lock.json ] && grep -q "BlueWallet/react-native-qrcode-local-image" package-lock.json 2>/dev/null; then
    print_header 3 "Patching @remobile/react-native-qrcode-local-image URL in package-lock.json"
    sed -i 's|BlueWallet/react-native-qrcode-local-image|remobile/react-native-qrcode-local-image|g' package-lock.json
fi

# BlueWallet/rn-qr-generator → rn-qr-generator ^1.0.0
patch_git_dep_json "rn-qr-generator" "BlueWallet/rn-qr-generator" "^1.0.0"
patch_git_dep_lock "rn-qr-generator" "BlueWallet/rn-qr-generator" "^1.0.0"

# aprock/react-native-tcp / BlueWallet/react-native-tcp → react-native-tcp ^3.3.0
patch_git_dep_json "react-native-tcp" "aprock/react-native-tcp" "^3.3.0"
patch_git_dep_json "react-native-tcp" "BlueWallet/react-native-tcp" "^3.3.0"
patch_git_dep_lock "react-native-tcp" "aprock/react-native-tcp" "^3.3.0"
patch_git_dep_lock "react-native-tcp" "BlueWallet/react-native-tcp" "^3.3.0"

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

print_header 2 "Detecting test infrastructure"

UNIT_SCRIPT=$(node -p "p=require('./package.json').scripts; (p.unit || '')")
INTEGRATION_SCRIPT=$(node -p "p=require('./package.json').scripts; (p.integration || '')")
JEST_SCRIPT=$(node -p "p=require('./package.json').scripts; (p.jest || '')")

HAS_UNIT=0; [ -n "$UNIT_SCRIPT" ] && HAS_UNIT=1
HAS_INTEGRATION=0; [ -n "$INTEGRATION_SCRIPT" ] && HAS_INTEGRATION=1
HAS_JEST=0; [ -n "$JEST_SCRIPT" ] && HAS_JEST=1

print_header 4 "unit:         $UNIT_SCRIPT (has=$HAS_UNIT)"
print_header 4 "integration:  $INTEGRATION_SCRIPT (has=$HAS_INTEGRATION)"
print_header 4 "jest:         $JEST_SCRIPT (has=$HAS_JEST)"

if [ $HAS_UNIT -eq 0 ] && [ $HAS_INTEGRATION -eq 0 ] && [ $HAS_JEST -eq 0 ]; then
    print_header 2 "NOT APPLICABLE" "No test scripts found at this commit"
    exit 2
fi

print_header 2 "Running tests with coverage"

# --- Unit tests ---
# "unit" script: mocha tests/unit/* (earliest) → jest tests/unit/* with flags
if [ $HAS_UNIT -eq 1 ]; then
    print_header 3 "Running unit tests"

    if echo "$UNIT_SCRIPT" | grep -q "mocha"; then
        print_header 4 "Unit tests use mocha — wrapping with c8"
        set +e
        npx --registry="$WAYPACK_NPM_REGISTRY" c8 --reporter=lcov mocha tests/unit/* --no-bail
        UNIT_EXIT=$?
        set -e
    else
        print_header 4 "Unit tests use jest — using built-in --coverage"
        set +e
        npx --registry="$WAYPACK_NPM_REGISTRY" jest tests/unit/* --runInBand --forceExit --coverage --coverageReporters=lcov
        UNIT_EXIT=$?
        set -e
    fi

    print_header 2 "Collecting unit test coverage reports"
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
fi

# --- Integration tests ---
# "jest" script (older) → "integration" script (newer): both run jest tests/integration/*
if [ $HAS_INTEGRATION -eq 1 ] || [ $HAS_JEST -eq 1 ]; then
    print_header 3 "Running integration tests"

    set +e
    npx --registry="$WAYPACK_NPM_REGISTRY" jest tests/integration/* --runInBand --forceExit --coverage --coverageReporters=lcov
    INTEGRATION_EXIT=$?
    set -e

    print_header 2 "Collecting integration test coverage reports"
    bash /coverage_reloaded/find-and-move-lcov.sh "integration" "false" "$INTEGRATION_EXIT"
fi

print_header 1 "BlueWallet coverage run complete"