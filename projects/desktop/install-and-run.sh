#!/usr/bin/env bash
set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/resolve-and-pin.sh
source /coverage_reloaded/na-if-focus-marker.sh
source /coverage_reloaded/assert-suite-ran.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    not_applicable "No package.json at this commit"
fi

if [ "$IS_YARN_MAIN_PM" != "true" ]; then
    print_header 2 "ERROR: unsupported package manager" "desktop uses yarn, but resolved to '$package_manager'"
    exit 1
fi

resolve_and_pin "electronjs.org"
resolve_and_pin "artifacts.electronjs.org"

FOCUS_PATHS=("app/test/unit")
if [ -d "script" ]; then
    FOCUS_PATHS+=("script")
fi
if [ -d "eslint-rules" ]; then
    FOCUS_PATHS+=("eslint-rules")
fi
na_if_focus_marker --runner jest --runner node "${FOCUS_PATHS[@]}"

export ELECTRON_MIRROR="http://waypack:3000/request/https://github.com/electron/electron/releases/download/"
# node-gyp resolves `disturl` from this environment variable ahead of any project
# .npmrc, and a run has one value for both installs. The app/ install (Electron
# addons: desktop-trampoline, desktop-notifications, registry-js, keytar, …) is the
# overwhelming majority of native builds and needs the Electron headers path, so
# that is the value. Root-level *Node*-target addons (e.g. vendor/printenvz, ~1% of
# commits) cannot be served by it — pointing the variable at Node instead makes
# every app/ build 404 — so that case is documented as an accepted gap in the
# project OVERVIEW rather than special-cased here.
export npm_config_disturl="http://waypack:3000/request/https://artifacts.electronjs.org/headers/dist"
echo "disturl=http://waypack:3000/request/https://artifacts.electronjs.org/headers/dist" >> ~/.npmrc
# A single WayPack 500 while node-gyp fetched a checksum file (SHASUMS256.txt) after
# successfully fetching the headers tarball aborted one run; node-gyp's downloader
# honours npm's fetch-retries, so give transient mirror errors more chances.
export npm_config_fetch_retries=5
export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=4096"

# ── Pre-seed node-gyp's Node-header cache ────────────────────────────────────
# `npm_config_disturl` must stay on the *Electron* headers path: the app's addons are
# the overwhelming majority of native builds and the env var outranks app/.npmrc. A
# root-level *Node*-target addon (rare — vendored deps such as printenvz) then asks
# for Node headers on that path and 404s. node-gyp installs headers under
# <cache>/node-gyp/<version>/ and reuses them when the directory exists with a
# current `installVersion` marker, so seeding the *running* Node version's entry lets
# those builds succeed without changing disturl for anything else: Electron builds
# key their cache on the Electron version and keep downloading from the Electron path.
NODE_HEADERS_VERSION="$(node -v | sed 's/^v//')"
GYP_INSTALL_VERSION=""
for gyp_pkg in /root/n/lib/node_modules/npm/node_modules/node-gyp/package.json \
               /usr/lib/node_modules/npm/node_modules/node-gyp/package.json; do
    if [ -f "$gyp_pkg" ]; then
        GYP_INSTALL_VERSION="$(node -p "try{require('$gyp_pkg').installVersion}catch(e){''}" 2>/dev/null)"
        [ -n "$GYP_INSTALL_VERSION" ] && break
    fi
done
[ -n "$GYP_INSTALL_VERSION" ] || GYP_INSTALL_VERSION=9
NODE_HEADERS_URL="http://waypack:3000/request/https://nodejs.org/download/release/v${NODE_HEADERS_VERSION}/node-v${NODE_HEADERS_VERSION}-headers.tar.gz"
for gyp_cache_root in "${XDG_CACHE_HOME:-$HOME/.cache}/node-gyp" "$HOME/.node-gyp"; do
    gyp_devdir="${gyp_cache_root}/${NODE_HEADERS_VERSION}"
    [ -f "${gyp_devdir}/installVersion" ] && continue
    mkdir -p "$gyp_devdir"
    set +e
    curl -fsSL "$NODE_HEADERS_URL" | tar -xz -C "$gyp_devdir" --strip-components=1
    seed_rc=$?
    set -e
    if [ "$seed_rc" -eq 0 ]; then
        echo "$GYP_INSTALL_VERSION" > "${gyp_devdir}/installVersion"
        print_header 4 "Pre-seeded node-gyp headers" "Node ${NODE_HEADERS_VERSION}, installVersion ${GYP_INSTALL_VERSION} → ${gyp_devdir}"
    else
        print_header 4 "NOTICE: pre-seeding Node headers failed (rc=$seed_rc) — continuing; a root-level Node addon may fail to build" "$NODE_HEADERS_URL"
    fi
done

rm -f .gitmodules

Xvfb :99 -screen 0 1280x1024x24 &
export DISPLAY=:99
yarn config set registry "$WAYPACK_YARN_REGISTRY"
yarn install --ignore-engines

# ── Environment fix for the 2022-05-10 -> 2023-12-11 window ──────────────────
# The defect is ours, not the project's: upstream CI was green throughout,
# because it stopped running coverage on 2022-05-04 and its runners are Ubuntu.
# Nothing here touches test code or test config. (The window's second defect —
# the era's dugite git needing glibc >= 2.32 — is fixed in the Dockerfile.)

# (1) Coverage instrumentation cannot parse the native class fields that
#     `tsconfig.json` `target: ES2022` (raised from es2017 on 2022-05-10) emits.
#     In this window the project declares no @babel/* at all, so the parser used
#     by the coverage path (babel-plugin-istanbul 6 -> istanbul-lib-instrument 4
#     -> @babel/core ^7.7.5 -> @babel/parser 7.12.7) predates class-field parsing
#     (7.14); every suite that imports such a module then fails to load with
#     "Support for the experimental syntax 'classProperties' isn't enabled".
#     Upstream fixed it in the ts5 merge (2023-12-11) by moving to jest 29 and
#     pinning @babel/core; do the same, and only where it is actually needed.
#     7.17.10 is the newest version present in WayPack's commit-dated view at the
#     window's opening commit (2022-05-10), so the pin resolves everywhere in the
#     window without stepping outside that view, and it is one uniform version
#     rather than a moving range.
BABEL_PARSER_VERSION=$(node -p "try{require('@babel/parser/package.json').version}catch(e){''}" 2>/dev/null || true)
TS_TARGET=$(node -p "try{require('./tsconfig.json').compilerOptions.target}catch(e){''}" 2>/dev/null || true)
if [ -n "$BABEL_PARSER_VERSION" ] &&
    node -e "const [a,b]=('$BABEL_PARSER_VERSION').split('.').map(Number);process.exit(a<7||(a===7&&b<14)?0:1)" &&
    printf '%s' "$TS_TARGET" | grep -qE '^ES(2022|2023|2024|Next)$'; then
    print_header 4 "Pinning @babel/core/@babel/parser for coverage instrumentation" \
        "parser $BABEL_PARSER_VERSION with target $TS_TARGET"
    node -e "
        const fs = require('fs');
        const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
        pkg.resolutions = Object.assign({}, pkg.resolutions,
            { '@babel/core': '7.17.10', '@babel/parser': '7.17.10' });
        fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
    "
    yarn install --ignore-scripts
fi

if [ -f script/test.mjs ]; then
    suite_start "unit" "Running unit tests with Node test runner"
    UNIT_LOG=$(mktemp)
    set +e
    npx --yes --registry="$VERDACCIO_REGISTRY" c8 --reporter=lcov node script/test.mjs 2>&1 | tee "$UNIT_LOG"
    UNIT_EXIT=${PIPESTATUS[0]}
    set -e
    assert_suite_ran "unit" "node" "$UNIT_LOG" "$UNIT_EXIT"
    rm -f "$UNIT_LOG"
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
    suite_end "unit" "$UNIT_EXIT"
else
    suite_start "unit" "Running unit tests with Jest"
    UNIT_LOG=$(mktemp)
    set +e
    yarn test:unit --coverage --coverageReporters=lcov --runInBand 2>&1 | tee "$UNIT_LOG"
    UNIT_EXIT=${PIPESTATUS[0]}
    set -e
    assert_suite_ran "unit" "jest" "$UNIT_LOG" "$UNIT_EXIT"
    rm -f "$UNIT_LOG"
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
    suite_end "unit" "$UNIT_EXIT"
fi

HAS_SCRIPT_TEST=$(node -p "!!((require('./package.json').scripts||{})['test:script'])")
if [ "$HAS_SCRIPT_TEST" = "true" ]; then
    suite_start "script" "Running script tests"
    SCRIPT_LOG=$(mktemp)
    set +e
    if [ -f script/test.mjs ]; then
        npx --yes --registry="$VERDACCIO_REGISTRY" c8 --reporter=lcov node script/test.mjs script 2>&1 | tee "$SCRIPT_LOG"
        SCRIPT_EXIT=${PIPESTATUS[0]}
    else
        yarn test:script --coverage --coverageReporters=lcov --runInBand 2>&1 | tee "$SCRIPT_LOG"
        SCRIPT_EXIT=${PIPESTATUS[0]}
    fi
    set -e
    if [ -f script/test.mjs ]; then
        assert_suite_ran "script" "node" "$SCRIPT_LOG" "$SCRIPT_EXIT"
    else
        assert_suite_ran "script" "jest" "$SCRIPT_LOG" "$SCRIPT_EXIT"
    fi
    rm -f "$SCRIPT_LOG"
    bash /coverage_reloaded/find-and-move-lcov.sh "script" "false" "$SCRIPT_EXIT"
    suite_end "script" "$SCRIPT_EXIT"
fi

# The eslint suite is deliberately not collected. `test:eslint` exercises the
# project's *custom lint rules* with ESLint's RuleTester, asserting diagnostics on
# inline code strings; no product code runs, and its lcov covers only
# `eslint-rules/**`. It is also not part of the project's own coverage intent: there
# is no `test:eslint:cov`, the root `test` script never runs it, CI does not run it,
# and the codecov upload reads the unit run's coverage only. See the project
# OVERVIEW ("Coverage collection" → Suites excluded).
