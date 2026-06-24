#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

print_header 2 "Installing dependencies"

# Metriport uses npm exclusively across its entire history.
if $IS_NPM_MAIN_PM; then
    # Era detection: early commits have a nested workspace at packages/
    # with @metriport/api and other SDK packages as local workspaces.
    # The root workspace (api/app, connect-widget/app, infra) depends on
    # @metriport/* packages as external npm deps, but they are not available
    # in the WayPack registry. We pack them as tarballs and rewrite deps
    # to point to the local files, bypassing WayPack entirely.
    if [ -f packages/package.json ]; then
        print_header 3 "Detected nested workspace at packages/ — building and publishing local SDK packages"
        cd packages
        npm install
        # Build all SDK packages (lerna run tsc) so @metriport/api is compiled
        print_header 4 "Building SDK packages with lerna"
        npm run build
        # Pack all @metriport/* packages into tarballs and rewrite the root
        # workspace's package.json to reference them via file: dependencies.
        # This avoids publishing to verdaccio (which would record today's
        # timestamp server-side, breaking WayPack's timestamp-pinned registry).
        cd /coverage_reloaded/repo
        print_header 4 "Packing all @metriport/* packages from packages/packages/"
        mkdir -p /tmp/metriport-packs
        ALL_PKGS=$(find packages/packages -maxdepth 1 -type d -not -name packages | sort)
        for PKG_DIR in $ALL_PKGS; do
            PKG_NAME=$(node -e "console.log(require('./${PKG_DIR}/package.json').name)")
            print_header 4 "Packing $PKG_NAME from $PKG_DIR"
            TARBALL=$(cd "$PKG_DIR" && npm pack --pack-destination /tmp/metriport-packs 2>/dev/null | tail -1)
            # Rewrite the root workspace's package.json to point this dep to the tarball
            # e.g. "@metriport/api": "file:/tmp/metriport-packs/metriport-api-1.0.0.tgz"
            node -e "
                const wsDirs = ['api/app', 'connect-widget/app', 'infra'];
                for (const w of wsDirs) {
                    try {
                        const wpj = require('./' + w + '/package.json');
                        if (wpj.dependencies && wpj.dependencies['$PKG_NAME']) {
                            console.log('  -> Rewriting ' + w + ' dep $PKG_NAME to file:$TARBALL');
                            wpj.dependencies['$PKG_NAME'] = 'file:/tmp/metriport-packs/$TARBALL';
                            require('fs').writeFileSync('./' + w + '/package.json', JSON.stringify(wpj, null, 2) + '\n');
                        }
                    } catch(e) {}
                }
            "
        done
        # Delete the root lockfile so npm re-resolves with local tarballs
        print_header 4 "Removing root lockfile for clean resolution"
        rm -f package-lock.json
    fi
    npm install --ignore-engines
else
    print_header 2 "main package manager not configured"
    exit 1
fi

print_header 2 "Detecting test infrastructure"

TEST_SCRIPT=$(node -p "require('./package.json').scripts.test || ''")

# Check if the test script is a no-op (echo "No test specified")
if [ -z "$TEST_SCRIPT" ] || echo "$TEST_SCRIPT" | grep -q "No test specified"; then
    print_header 2 "NOT APPLICABLE" "No real test script found at this commit"
    exit 2
fi

print_header 4 "test script: $TEST_SCRIPT"

# Metriport has no native coverage tooling (no c8/nyc in devDeps at any point).
# We wrap the test command with c8 to collect V8 coverage.
print_header 2 "Installing c8 for coverage collection"
npm install --no-save c8

# Era detection: run-tests.sh (GNU parallel) vs. inline npm workspaces script
if [ -f packages/scripts/run-tests.sh ]; then
    print_header 2 "Era: run-tests.sh (GNU parallel)"
    CMD="bash packages/scripts/run-tests.sh"
else
    print_header 2 "Era: npm workspaces"
    CMD="$TEST_SCRIPT"
fi

print_header 3 "Running: c8 --reporter=lcov $CMD"
set +e
npx --registry="$WAYPACK_NPM_REGISTRY" c8 --reporter=lcov bash -c "$CMD"
TEST_EXIT=$?
set -e

print_header 2 "Collecting coverage reports"
bash /coverage_reloaded/find-and-move-lcov.sh "unit" "true" "$TEST_EXIT"

print_header 1 "Metriport coverage run complete"
