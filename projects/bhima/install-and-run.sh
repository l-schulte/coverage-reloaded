#!/bin/bash

set -e

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/fake-time.sh"

cd /coverage_reloaded/repo

# ── Dependency installation ───────────────────────────────────────────────────

# Activate sample env if no .env exists
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

# Load env vars
set -a
source .env
set +a

if $IS_NPM_MAIN_PM; then
    print_header 2 "Installing dependencies with npm..."
    npm install
    PM_RUN="npm run"

elif $IS_YARN_MAIN_PM; then
    print_header 2 "Installing dependencies with yarn..."
    yarn install || true
    npm install --no-save --force
    PM_RUN="yarn run"
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

npm install -g cross-env lodash

node -e "require('c8')" 2>/dev/null \
    || npm install --no-save c8 2>&1 | tail -3 \
    || { echo "FATAL: could not install c8"; exit 1; }

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

if [ -f bin/client/js/bhima/bhima.min.js ]; then
    echo "Client bundle present: bin/client/js/bhima/bhima.min.js"
    BUNDLE_AVAILABLE=true
else
    echo "NOTICE: bin/client/js/bhima/bhima.min.js not found — client-unit coverage will be skipped"
    BUNDLE_AVAILABLE=false
fi

# ── Client coverage era detection ─────────────────────────────────────────────

if ! $BUNDLE_AVAILABLE; then
    CLIENT_ERA="no_bundle"
    echo "Client coverage era: no bundle — skipping client-unit entirely"
elif grep -qE "'coverage'|\"coverage\"" karma.conf.js 2>/dev/null \
     && node -e "require('./node_modules/karma-coverage')" 2>/dev/null; then
    CLIENT_ERA="project_coverage"
    echo "Client coverage era: project configures karma-coverage — using project config as-is"
elif [ -f bin/client/js/bhima/bhima.min.js.map ]; then
    CLIENT_ERA="sourcemap"
    echo "Client coverage era: source maps present — supplemental karma-coverage config will be injected"
else
    CLIENT_ERA="no_sourcemap"
    echo "Client coverage era: bundle present but no source maps — client-unit coverage cannot be collected"
fi

mkdir -p coverage/server coverage/client

# ── Start MySQL ────────────────────────────────────────────────────────────────

print_header 2 "Starting MySQL server"

if node -e "require('./package.json').scripts['build:db'] || process.exit(1)" 2>/dev/null; then
    print_header 3 "Database build script detected: build:db"

    # Start MySQL, but fake the time since some integration test rely on timestamps 
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

    # fake_time bash -x sh/build-database.sh
    $PM_RUN build:db || { echo "ERROR: database build failed" >&2; exit 1; }
else
    print_header 3 "No database build script detected — skipping MySQL setup"
fi

# ── Server-unit tests with c8 ─────────────────────────────────────────────────

print_header 2 "Running server-unit tests with c8 coverage"

export CHROMIUM_FLAGS="--no-sandbox --disable-setuid-sandbox"
export PUPPETEER_LAUNCH_OPTIONS='{"args":["--no-sandbox","--disable-setuid-sandbox"]}'
export PUPPETEER_ARGS="--no-sandbox --disable-setuid-sandbox"


set +e

if [ "$SERVER_ERA" = "mocha_direct" ]; then
    C8_OUTPUT=$(./node_modules/.bin/c8 \
        --reporter=lcov \
        --reporter=text-summary \
        --include='server/**/*.js' \
        --exclude='test/**' \
        --output-dir=coverage/server \
        ./node_modules/.bin/mocha \
            --recursive \
            --no-bail \
            --exit \
            test/server-unit 2>&1)
    SERVER_EXIT=$?
else
    C8_OUTPUT=$(./node_modules/.bin/c8 \
        --reporter=lcov \
        --reporter=text-summary \
        --include='server/**/*.js' \
        --exclude='test/**' \
        --output-dir=coverage/server \
        bash sh/server-unit-tests-node.sh 2>&1)
    SERVER_EXIT=$?
fi

echo "$C8_OUTPUT"

set -e

if [ $SERVER_EXIT -ne 0 ]; then
    # A "Cannot find module" error means mocha crashed during loadFiles —
    # no test bodies executed and any coverage produced is instrumentation
    # noise from require() traversal. This is not usable data.
    if echo "$C8_OUTPUT" | grep -q "Cannot find module"; then
        MISSING_MODULE=$(echo "$C8_OUTPUT" | grep "Cannot find module" | head -3)
        echo "FATAL: Mocha crashed during file loading — no tests executed"
        echo "       Coverage data is instrumentation noise and will not be collected."
        echo "       Missing modules:"
        echo "$MISSING_MODULE"
        echo ""
        echo "       This indicates a WayPack registry miss for this commit timestamp."
        exit 1
    fi

    # Tests ran but some failed — coverage is partial but represents real
    # test execution. Preserve it with a warning.
    echo "WARNING: server-unit tests exited with code $SERVER_EXIT — coverage data preserved but may be partial"
fi

bash /coverage_reloaded/find-and-move-lcov.sh "server" "false" "$SERVER_EXIT"

# ── Client-unit tests with karma coverage ─────────────────────────────────────

print_header 2 "Running client-unit tests"

set +e

if [ "$CLIENT_ERA" = "project_coverage" ]; then
    ./node_modules/.bin/karma start karma.conf.js \
        --single-run \
        --no-auto-watch
    KARMA_EXIT=$?

elif [ "$CLIENT_ERA" = "sourcemap" ]; then
    node -e "require('karma-coverage')"         2>/dev/null || npm install --no-save karma-coverage         2>&1 | tail -3
    node -e "require('karma-sourcemap-loader')" 2>/dev/null || npm install --no-save karma-sourcemap-loader 2>&1 | tail -3

    cat > /tmp/karma.conf.coverage.js << 'KARMA_EOF'
const base = require('/coverage_reloaded/repo/karma.conf.js');

module.exports = (config) => {
  base(config);

  const pp = config.preprocessors || {};
  const bundleKey = 'bin/client/js/bhima/bhima.min.js';
  pp[bundleKey] = (pp[bundleKey] || []).concat(['sourcemap', 'coverage']);
  config.set({ preprocessors: pp });

  const reporters = (config.reporters || []).filter(r => r !== 'coverage');
  reporters.push('coverage');

  config.set({
    reporters,
    coverageReporter : {
      type : 'lcovonly',
      dir  : '/coverage_reloaded/repo/coverage/client',
      file : 'lcov.info',
    },
  });
};
KARMA_EOF

    ./node_modules/.bin/karma start /tmp/karma.conf.coverage.js \
        --single-run \
        --no-auto-watch
    KARMA_EXIT=$?

else
    echo "NOTICE: Skipping client-unit coverage (era: $CLIENT_ERA)"
    KARMA_EXIT=0
fi

set -e

if [ "$CLIENT_ERA" = "project_coverage" ] || [ "$CLIENT_ERA" = "sourcemap" ]; then
    [ $KARMA_EXIT -ne 0 ] && \
        echo "WARNING: client-unit tests exited with code $KARMA_EXIT — coverage data preserved but may be partial"
    bash /coverage_reloaded/find-and-move-lcov.sh "client" "false" "$KARMA_EXIT"
else
    echo "Client coverage skipped (era: $CLIENT_ERA) — server coverage is the sole source for this commit"
fi