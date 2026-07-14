#!/bin/bash

set -e

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/fake-time.sh"

cd /coverage_reloaded/repo

# ── Dependency installation ───────────────────────────────────────────────────

print_header 2 "Setting up environment variables"

if [ ! -f .env ]; then
    env_files=(.env.sample .env.example .env.development .env.dev .env.*)
    for env_file in "${env_files[@]}"; do
        if [ -f "$env_file" ]; then
            cp "$env_file" .env
            echo "No .env file found, copied $env_file to .env"
            break
        fi
    done
else
    echo ".env file found, using existing environment variables"
fi

set -a
source .env
set +a

if $IS_NPM_MAIN_PM; then
    print_header 2 "Installing dependencies with npm..."
    npm install
    PM_RUN="npm run"
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

npm install -g cross-env lodash

node -e "require('c8')" 2>/dev/null \
    || npm install --no-save c8 2>&1 | tail -3 \
    || { echo "FATAL: could not install c8"; exit 1; }

# ── Symlink harness coverage tools into project node_modules ──────────────────
# Done after npm install so node_modules/ exists.
# These are only used by the karma sidecar config — harmless for non-Karma eras.

print_header 2 "Symlinking harness coverage tools"

ln -sf /coverage_reloaded/harness/node_modules/karma-coverage \
       /coverage_reloaded/repo/node_modules/karma-coverage
ln -sf /coverage_reloaded/harness/node_modules/@babel/core \
       /coverage_reloaded/repo/node_modules/@babel/core
ln -sf /coverage_reloaded/harness/node_modules/@babel/preset-env \
       /coverage_reloaded/repo/node_modules/@babel/preset-env
ln -sf /coverage_reloaded/harness/node_modules/karma-babel-preprocessor \
       /coverage_reloaded/repo/node_modules/karma-babel-preprocessor

echo "Symlinks created"

TEST_SCRIPT=$(node -p "require('./package.json').scripts['test'] || ''")

# ── Era detection ─────────────────────────────────────────────────────────────

print_header 2 "Detecting test infrastructure era"

if [ -f sh/server-unit-tests-node.sh ]; then
    SERVER_ERA="shell_script"
    echo "Server-unit era: delegated (sh/server-unit-tests-node.sh)"
else
    SERVER_ERA="mocha_direct"
    echo "Server-unit era: direct mocha invocation"
fi

# ── Build client bundle ───────────────────────────────────────────────────────

print_header 2 "Building client bundle"

set +e
BUILD_EXIT=0
for SCRIPT_NAME in build "build:client" compile; do
    SCRIPT_EXISTS=$(node -p "require('./package.json').scripts['${SCRIPT_NAME}'] ? 'yes' : 'no'" 2>/dev/null)
    if [ "$SCRIPT_EXISTS" = "yes" ]; then
        echo "Attempting build via: $PM_RUN $SCRIPT_NAME"
        $PM_RUN "$SCRIPT_NAME" 2>&1
        BUILD_EXIT=$?
        [ $BUILD_EXIT -ne 0 ] && echo "WARNING: build script '$SCRIPT_NAME' exited with code $BUILD_EXIT"
        break
    fi
done
set -e

mkdir -p coverage/server coverage/client

# ── Start MySQL ───────────────────────────────────────────────────────────────

print_header 2 "Starting MySQL server"

if node -e "require('./package.json').scripts['build:db'] || process.exit(1)" 2>/dev/null; then
    print_header 3 "Database build script detected: build:db"

    fake_time mysqld_safe \
      --datadir=/var/lib/mysql \
      --sql-mode="STRICT_ALL_TABLES,NO_UNSIGNED_SUBTRACTION" \
      --character-set-server=utf8mb4 \
      --collation-server=utf8mb4_unicode_ci &

    until mysqladmin ping -h 127.0.0.1 --silent 2>/dev/null; do
        sleep 1
    done

    mysql -u root -e "CREATE USER '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASS';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'$DB_HOST' WITH GRANT OPTION;"
    mysql -u root -e "FLUSH PRIVILEGES;"

    NODE_OPTIONS="-r /coverage_reloaded/fake-time-node.js $NODE_OPTIONS" \
    TIMESTAMP_EPOCH="$timestamp" \
    $PM_RUN build:db || { echo "ERROR: database build failed" >&2; exit 1; }
else
    print_header 3 "No database build script detected — skipping MySQL setup"
fi

# ── Start Redis ───────────────────────────────────────────────────────────────

print_header 2 "Starting Redis server"

redis-server --daemonize yes
redis-cli ping

# ── Server-unit tests with c8 ─────────────────────────────────────────────────

suite_start "server-unit" "Running server-unit tests with c8 coverage (${SERVER_ERA})"

export CHROMIUM_FLAGS="--no-sandbox --disable-setuid-sandbox"
export PUPPETEER_LAUNCH_OPTIONS='{"args":["--no-sandbox","--disable-setuid-sandbox"]}'
export PUPPETEER_ARGS="--no-sandbox --disable-setuid-sandbox"

set +e

if [ "$SERVER_ERA" = "mocha_direct" ]; then
    C8_OUTPUT=$(./node_modules/.bin/c8 \
        --reporter=lcov \
        ./node_modules/.bin/mocha \
            --recursive \
            --no-bail \
            --exit \
            test/server-unit 2>&1)
    SERVER_EXIT=$?
else
    C8_OUTPUT=$(./node_modules/.bin/c8 \
        --reporter=lcov \
        bash sh/server-unit-tests-node.sh 2>&1)
    SERVER_EXIT=$?
fi

echo "$C8_OUTPUT"

set -e

bash /coverage_reloaded/find-and-move-lcov.sh "server" "false" "$SERVER_EXIT"
suite_end "server-unit" "$SERVER_EXIT"

# ── Client-unit tests with karma-coverage ─────────────────────────────────────

suite_start "client-unit" "Running client-unit tests with karma-coverage"

test -f /coverage_reloaded/repo/bin/client/js/bhima/bhima.min.js \
    || { echo "FATAL: bhima.min.js not found — build did not produce expected output"; exit 1; }

set +e
./node_modules/.bin/karma start \
    /coverage_reloaded/harness/karma.sidecar.conf.js \
    2>&1 | tee /tmp/karma.log
KARMA_EXIT=$?
set -e

LCOV=/coverage_reloaded/harness/output/lcov.info

test -f "$LCOV" \
    || { echo "FATAL: lcov.info not produced — karma-coverage did not fire"; exit 1; }

# Instrumentation-caused DI failures silently corrupt coverage data
grep -q "Function.prototype.bind.apply.*is not a constructor" /tmp/karma.log \
    && { echo "FATAL: AngularJS DI failures detected — babel transpilation broken"; exit 1; }

DA_NONZERO=$(grep -c "^DA:.*,[1-9]" "$LCOV" || echo 0)
[ "$DA_NONZERO" -eq 0 ] \
    && { echo "FATAL: all DA entries zero — instrumentation did not reach test execution"; exit 1; }

cp "$LCOV" /coverage_reloaded/repo/coverage/client/lcov.info
rm -f "$LCOV"

bash /coverage_reloaded/find-and-move-lcov.sh "client" "false" "$KARMA_EXIT"
suite_end "client-unit" "$KARMA_EXIT"
# exit
# ── Integration tests with c8 ─────────────────────────────────────────────────

HAS_INTEGRATION=$(node -p "require('./package.json').scripts['test:integration'] ? 'yes' : 'no'" 2>/dev/null)
if [ "$HAS_INTEGRATION" = "yes" ] && [ -n "$(node -p "require('./package.json').scripts['test:integration'] || ''")" ]; then
    suite_start "integration" "Running integration tests with c8 coverage"

    set +e
    NODE_OPTIONS="-r /coverage_reloaded/fake-time-node.js $NODE_OPTIONS" \
    TIMESTAMP_EPOCH="$timestamp" \
    ./node_modules/.bin/c8 \
        --reporter=lcov \
        ./node_modules/.bin/mocha \
            test/integration \
            --recursive \
            --no-bail \
            --exit
    INTEGRATION_EXIT=$?
    set -e

    bash /coverage_reloaded/find-and-move-lcov.sh "integration" "false" "$INTEGRATION_EXIT"
    suite_end "integration" "$INTEGRATION_EXIT"

    # Kill the bhima server so the next suite can bind to port 8080
    lsof -ti :8080 2>/dev/null | xargs -r kill 2>/dev/null || true
fi

# ── Stock integration tests with c8 ──────────────────────────────────────────

HAS_STOCK_INTEGRATION=$(node -p "require('./package.json').scripts['test:integration:stock'] ? 'yes' : 'no'" 2>/dev/null)
if [ "$HAS_STOCK_INTEGRATION" = "yes" ] && [ -n "$(node -p "require('./package.json').scripts['test:integration:stock'] || ''")" ]; then
    # Stock integration tests require a different database build
    # (sh/build-stock-database.sh) that loads test/data/service-stock.sql
    # containing the depot UUIDs (e.g. 4341f89c...) expected by the stock tests.
    print_header 3 "Rebuilding database with stock-specific seed data"
    HAS_BUILD_STOCK=$(node -p "require('./package.json').scripts['build:stock'] ? 'yes' : 'no'" 2>/dev/null)
    if [ "$HAS_BUILD_STOCK" = "yes" ]; then
        NODE_OPTIONS="-r /coverage_reloaded/fake-time-node.js $NODE_OPTIONS" \
        TIMESTAMP_EPOCH="$timestamp" \
        $PM_RUN build:stock
    else
        print_header 4 "ERROR: expected build:stock script, but none found. Panic!"
        exit 1
    fi
    echo "Database rebuild completed"

    suite_start "integration-stock" "Running stock integration tests with c8 coverage"

    set +e
    NODE_OPTIONS="-r /coverage_reloaded/fake-time-node.js $NODE_OPTIONS" \
    TIMESTAMP_EPOCH="$timestamp" \
    ./node_modules/.bin/c8 \
        --reporter=lcov \
        ./node_modules/.bin/mocha \
            test/integration-stock \
            --recursive \
            --no-bail \
            --exit
    INTEGRATION_STOCK_EXIT=$?
    set -e

    bash /coverage_reloaded/find-and-move-lcov.sh "integration-stock" "false" "$INTEGRATION_STOCK_EXIT"
    suite_end "integration-stock" "$INTEGRATION_STOCK_EXIT"
fi