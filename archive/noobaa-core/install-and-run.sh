#!/bin/bash

# ── NooBaa Core — install-and-run.sh ─────────────────────────
#
# Always start both MongoDB and PostgreSQL (both are in the image).
# An unused DB is harmless; a missing needed DB breaks tests.
# Test suites are selected by inspecting package.json scripts.
#
# ──────────────────────────────────────────────────────────────

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

set -e
cd /coverage_reloaded/repo

# ══════════════════════════════════════════════════════════════
# 1. Detect which test suites to run
# ══════════════════════════════════════════════════════════════

print_header 1 "Detecting test suites"

HAS_MOCHA_SCRIPT=$(node -p "!!require('./package.json').scripts.mocha")
HAS_JEST_SCRIPT=$(node -p "!!require('./package.json').scripts.jest")
echo "  mocha script: $HAS_MOCHA_SCRIPT"
echo "  jest script:  $HAS_JEST_SCRIPT"

# ══════════════════════════════════════════════════════════════
# 2. Install dependencies
# ══════════════════════════════════════════════════════════════

print_header 2 "Installing dependencies"
npm install --no-fund --include=dev --legacy-peer-deps

# Build native addons (isa-l, snappy, cm256 via node-gyp)
BUILD_NATIVE_SCRIPT=$(node -p "require('./package.json').scripts['build:native'] || ''")
if [ -n "$BUILD_NATIVE_SCRIPT" ]; then
    print_header 2 "Building native addons"
    npm run build:native
fi

# ══════════════════════════════════════════════════════════════
# 3. Start database services
# ══════════════════════════════════════════════════════════════

print_header 2 "Starting MongoDB"
MONGODB_DBPATH=$(grep "dbPath" mongod.conf 2>/dev/null | awk '{print $2}' | tr -d ' ')
MONGODB_DBPATH="${MONGODB_DBPATH:-./metadata_storage}"
mkdir -p "$MONGODB_DBPATH"
mongod --dbpath "$MONGODB_DBPATH" --logpath /tmp/mongod.log --fork --bind_ip 127.0.0.1
print_header 4 "MongoDB started (dbPath=$MONGODB_DBPATH)"

print_header 2 "Starting PostgreSQL"
PG_DATA=/tmp/postgres_data
PG_BIN=/usr/lib/postgresql/12/bin
if [ ! -f "$PG_DATA/PG_VERSION" ]; then
    mkdir -p "$PG_DATA"
    chown postgres:postgres "$PG_DATA"
    su - postgres -c "$PG_BIN/initdb -D $PG_DATA -E UTF-8 --locale=C"
fi
su - postgres -c "$PG_BIN/pg_ctl -D $PG_DATA -l /tmp/postgres.log start"
su - postgres -c "psql -c \"CREATE USER noobaa WITH PASSWORD 'noobaa';\"" 2>/dev/null || true
su - postgres -c "psql -c \"CREATE DATABASE coretest OWNER noobaa;\"" 2>/dev/null || true
su - postgres -c "psql -c \"GRANT ALL ON SCHEMA public TO noobaa;\"" 2>/dev/null || true
export POSTGRES_HOST=localhost
export POSTGRES_USER=noobaa
export POSTGRES_PASSWORD=noobaa
print_header 4 "PostgreSQL started"

# ══════════════════════════════════════════════════════════════
# 4. Patch linux-blockutils in node_modules for container compat
# ══════════════════════════════════════════════════════════════

print_header 2 "Patching linux-blockutils in node_modules"

# linux-blockutils.getBlockInfo() can return sparse entries (including
# undefined) inside containers where /sys/block entries don't fully
# populate.  We patch the installed package in node_modules directly
# (not project source) so every process that imports it gets the fix.
#
# This is more reliable than a --require preload shim because it
# survives child process boundaries and works regardless of how the
# module is loaded (require, child_process.fork, etc.).
LINUX_BLOCKUTILS_JS="node_modules/linux-blockutils/blockutils.js"
if [ -f "$LINUX_BLOCKUTILS_JS" ]; then
    # Add .filter(Boolean) before the callback invocation to strip
    # undefined entries from the lsblk output array.
    # The library uses: callback(null, blockInfo);
    sed -i 's/callback(null, blockInfo);/callback(null, blockInfo.filter(Boolean));/' \
        "$LINUX_BLOCKUTILS_JS"
    print_header 4 "Patched $LINUX_BLOCKUTILS_JS"
else
    print_header 4 "WARNING: $LINUX_BLOCKUTILS_JS not found — skipping patch"
fi

# Smoke test: verify getBlockInfo returns clean data
print_header 4 "Smoke-testing linux-blockutils..."
node -e "
const b = require('linux-blockutils');
b.getBlockInfo({}, function(err, data) {
    if (err) { console.log('  ERROR:', err.message); process.exit(1); }
    const bad = data.filter(function(x) { return !x || x.NAME == null || x.SIZE == null; });
    console.log('  entries:', data.length, 'bad:', bad.length);
    if (bad.length > 0) { console.log('  FAIL: bad entries remain'); process.exit(1); }
    console.log('  OK');
});
"

# ══════════════════════════════════════════════════════════════
# 5. Run tests
# ══════════════════════════════════════════════════════════════

print_header 2 "Running tests"

# ── 5b. Mocha tests ──────────────────────────────────────────
if [ "$HAS_MOCHA_SCRIPT" = "true" ]; then
    suite_start "mocha" "Running Mocha tests with coverage"

    # Install mocha-multi for dual reporter (spec to stdout, json to file)
    npm install --no-fund mocha-multi 2>/dev/null || true

    json_out="/tmp/mocha-stats.json"
    rm -f "$json_out"

    set +e
    npx --registry=$VERDACCIO_REGISTRY nyc \
        --all \
        --include 'src/**/*.js' \
        --exclude 'src/util/mongo_functions.js' \
        --exclude 'src/util/panic.js' \
        --reporter lcov \
        npm run mocha -- \
            --reporter mocha-multi \
            --reporter-options spec=-,json="$json_out"
    MOCHA_EXIT=$?
    set -e

    # Verify that tests actually ran
    n_tests=$(node -e "try{process.stdout.write(String(require('$json_out').stats.tests))}catch(e){process.stdout.write('0')}" 2>/dev/null)

    if [ -z "$n_tests" ] || [ "$n_tests" = "0" ]; then
        print_header 4 "ERROR: Mocha reported 0 tests run (exit code $MOCHA_EXIT) — no tests executed"
        exit 1
    fi

    print_header 4 "Mocha finished: $n_tests tests run, exit code $MOCHA_EXIT"

    bash ../find-and-move-lcov.sh "mocha" "false" "$MOCHA_EXIT"
    suite_end "mocha" "$MOCHA_EXIT"
fi

# ── 5a. Jest tests ───────────────────────────────────────────
if [ "$HAS_JEST_SCRIPT" = "true" ]; then
    suite_start "jest" "Running Jest tests with coverage"

    set +e
    npx --registry=$WAYPACK_NPM_REGISTRY jest --coverage --no-bail --runInBand
    JEST_EXIT=$?
    set -e

    bash ../find-and-move-lcov.sh "jest" "false" "$JEST_EXIT"
    suite_end "jest" "$JEST_EXIT"
fi

# ══════════════════════════════════════════════════════════════
# 6. Cleanup database services
# ══════════════════════════════════════════════════════════════

print_header 2 "Stopping MongoDB"
mongod --dbpath "$MONGODB_DBPATH" --shutdown 2>/dev/null || true

print_header 2 "Stopping PostgreSQL"
su - postgres -c "$PG_BIN/pg_ctl -D $PG_DATA stop" 2>/dev/null || true

print_header 1 "Done"
