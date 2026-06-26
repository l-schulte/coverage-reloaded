#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

# Increase Node.js heap to prevent OOM during build and Jest coverage collection.
export NODE_OPTIONS="--max-old-space-size=12288"

print_header 2 "Installing dependencies"

INSTALL_FILTER_PATTERNS=(
    '➤ YN0013:'
    '➤ YN0007:'
)

INSTALL_GREP_ARGS=()
for pattern in "${INSTALL_FILTER_PATTERNS[@]}"; do
    INSTALL_GREP_ARGS+=(-e "$pattern")
done

CI= yarn install 2>&1 | grep --line-buffered -Fv "${INSTALL_GREP_ARGS[@]}"

# Yarn 3's node-modules linker hoists binaries to the root node_modules/.bin,
# but doesn't add it to PATH when running workspace scripts. Add it explicitly.
export PATH="/coverage_reloaded/repo/node_modules/.bin:$PATH"

HAS_WORKSPACES_FOREACH=$(yarn workspaces foreach --help >/dev/null 2>&1 && echo "yes" || echo "no")

# ── Dynamic feature detection ───────────────────────────────────────────────
# Detect what infrastructure exists at this commit rather than assuming eras.
HAS_PREPARE_JS=$(test -f bin/prepare.js && echo "yes" || echo "no")
HAS_FILTER_FLAG=$(node -e "try{process.exit(require('fs').readFileSync('bin/prepare.js','utf-8').includes('--filter')?0:1)}catch(e){process.exit(1)}" 2>/dev/null && echo "yes" || echo "no")
HAS_TCP_PG_CHECK=$(node -e "try{process.exit(require('fs').readFileSync('packages/cli/index.js','utf-8').includes('checkPostgresIsRunning')?0:1)}catch(e){process.exit(1)}" 2>/dev/null && echo "yes" || echo "no")
HAS_BUILD_DEPS=$(node -e "try{const p=require('./apps/condo/package.json');process.exit((p.scripts||{}).hasOwnProperty('build:deps')?0:1)}catch(e){process.exit(1)}" 2>/dev/null && echo "yes" || echo "no")
HAS_CONDO_WORKSPACE=$(test -f apps/condo/package.json && echo "yes" || echo "no")


print_header 2 "Running tests with coverage"

# nyc can't combine coverage across yarn workspaces, so rely on each workspace's
# own lcov.info and collect them afterwards.

# ── Start Docker daemon (Docker-in-Docker) ──────────────────────────────────
# The repo's docker-compose.yml defines postgresdb and redis services that
# bin/prepare.js interacts with via docker-compose exec. We start the Docker
# daemon inside the container, then use docker-compose to bring up the services.
print_header 3 "Starting Docker daemon (Docker-in-Docker)..."
# Configure dockerd to use the docker-cache registry mirror on the mining-net
# network. This avoids rate limits and speeds up pulls for postgres/redis images.
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": ["http://docker-cache:5000"],
  "dns": ["1.1.1.1", "8.8.8.8"]
}
EOF
dockerd &>/tmp/dockerd.log &
DOCKERD_PID=$!

# Wait for Docker daemon to be ready
for i in $(seq 1 30); do
    if docker info &>/dev/null; then break; fi
    sleep 1
done
docker info &>/dev/null || {
    echo "ERROR: Docker daemon failed to start"
    cat /tmp/dockerd.log
    exit 1
}

docker ps

# Some versions of @open-condo/cli call `docker-compose` (with hyphen) internally.
# The modern Docker CLI uses `docker compose` (with space). Create a compat shim.
if ! command -v docker-compose &>/dev/null; then
    cat > /usr/local/bin/docker-compose <<'COMPOSE_SHIM'
#!/bin/sh
exec docker compose "$@"
COMPOSE_SHIM
    chmod +x /usr/local/bin/docker-compose
fi

print_header 3 "Docker daemon is ready"

# ── Start postgresdb and redis via docker-compose ───────────────────────────
# Some docker-compose.yml versions use ${REGISTRY} as a prefix for image names
# (e.g. ${REGISTRY}postgres:16.8). Default to empty string so images resolve
# directly from Docker Hub (via the docker-cache mirror).
export REGISTRY=""
print_header 3 "Starting postgresdb and redis via docker compose..."
docker compose up -d postgresdb redis

# Wait for PostgreSQL to be ready inside the container
print_header 3 "Waiting for PostgreSQL to be ready..."
for i in $(seq 1 30); do
    if docker compose exec postgresdb bash -c "su -c 'psql -tAc \"select 1+1\" postgres' postgres" &>/dev/null; then
        docker ps
        print_header 3 "PostgreSQL is ready"
        break
    fi
    sleep 1
done

# Use fake address service client to avoid needing the address-service microservice.
# The code checks for ADDRESS_SERVICE_CLIENT_MODE=fake or NODE_ENV=test.
export ADDRESS_SERVICE_CLIENT_MODE=fake

# Copy .env.example → .env if .env doesn't exist yet.
# @open-condo/config reads from .env at startup, but safeExec strips process env
# vars — only .env files survive into child processes.
# Older versions of bin/prepare.js (Era 1-3) don't do this copy themselves.
if [ ! -f /coverage_reloaded/repo/.env ]; then
    print_header 3 "Copying .env.example → .env for default config..."
    cp /coverage_reloaded/repo/.env.example /coverage_reloaded/repo/.env
fi



# ── Build workspace dependencies ────────────────────────────────────────────
# Workspace packages like @open-condo/keystone, @open-condo/miniapp-utils, etc.
# need to be built before anything that imports them (migrations, server, tests).
# build:deps was introduced when turbo was added to the repo.
if [ "$HAS_BUILD_DEPS" = "yes" ]; then
    print_header 3 "Building workspace dependencies (build:deps)..."
    yarn workspace @app/condo build:deps
else
    print_header 3 "No build:deps script — skipping workspace dependency build"
fi

# ── Run the project's own prepare script ────────────────────────────────────
# bin/prepare.js sets up databases, env files, and runs migrations.
# It was introduced in Feb 2023. Before that, there's no prepare script.
if [ "$HAS_PREPARE_JS" = "yes" ]; then
    print_header 3 "Running bin/prepare.js to set up databases, env, migrations..."
    if [ "$HAS_FILTER_FLAG" = "yes" ]; then
        node bin/prepare.js --filter=condo
    else
        # Early versions of prepare.js don't support --filter and prepare all apps
        print_header 3 "prepare.js does not support --filter — preparing all apps"
        node bin/prepare.js
    fi
else
    print_header 3 "No bin/prepare.js — skipping database/env setup"
fi

# ── Build the Admin UI ──────────────────────────────────────────────────────
# Schema tests connect to a real Keystone server. The AdminUIApp requires built
# artifacts (dist/admin) which are produced by `keystone build`.
# We run the full project build pipeline to produce them.
if [ "$HAS_CONDO_WORKSPACE" = "yes" ]; then
    print_header 3 "Building Admin UI (keystone build)..."
    yarn workspace @app/condo build
else
    print_header 2 "No apps/condo workspace — nothing to build or test"
    exit 2
fi

# ── Read the actual port from apps/condo/.env ────────────────────────────────
# bin/prepare.js assigns ports sequentially (4000 + index), so condo may get
# port 4002. The tests read SERVER_URL from .env and connect there. We must
# start the server on whatever port prepare.js configured.
CONDO_PORT=$(grep -oP '^PORT=\K.*' apps/condo/.env 2>/dev/null || echo "3000")
CONDO_SERVER_URL="http://localhost:$CONDO_PORT"
print_header 3 "Condo will run on port $CONDO_PORT (SERVER_URL=$CONDO_SERVER_URL)"

# ── Start the Keystone server ───────────────────────────────────────────────
# Start the KeystoneJS server in the background on the port that prepare.js
# configured. The server will serve the GraphQL API and Admin UI that the
# schema tests connect to via HTTP (real client mode).
print_header 3 "Starting Keystone server on port $CONDO_PORT..."

PORT=$CONDO_PORT yarn workspace @app/condo start > >(grep -i 'error') 2>&1 &
KEYSTONE_PID=$!

# Wait for the server to be ready by polling the GraphQL endpoint
print_header 3 "Waiting for Keystone server to be ready at $CONDO_SERVER_URL/admin/api..."
for i in $(seq 1 60); do
    if curl -s "$CONDO_SERVER_URL/admin/api" >/dev/null 2>&1; then
        print_header 3 "Keystone server is ready"
        break
    fi
    if ! kill -0 $KEYSTONE_PID 2>/dev/null; then
        echo "ERROR: Keystone server died during startup"
        exit 1
    fi
    sleep 2
done

# ── Run tests ───────────────────────────────────────────────────────────────
# Run tests sequentially (--runInBand) — parallel workers cause duplicate key errors.
# Tests connect to the real Keystone server at $CONDO_SERVER_URL.
# We use `yarn workspace @app/condo test` (not `yarn workspaces foreach`) because
# yarn workspace sets CWD to apps/condo/, which lets @open-condo/config correctly
# load apps/condo/.env (with SERVER_URL, test credentials, etc.).
LOG_FILTER_PATTERNS=(
    '➤ YN0000: {'
    '[GraphQL >>>'
    '[GraphQL <<<'
    '{"level"'
)
GREP_ARGS=()
for pattern in "${LOG_FILTER_PATTERNS[@]}"; do
    GREP_ARGS+=(-e "$pattern")
done

set +e
set -o pipefail

if [ "$HAS_WORKSPACES_FOREACH" = "yes" ]; then
    # Run @app/condo individually so CWD is apps/condo/ and @open-condo/config
    # correctly loads apps/condo/.env (SERVER_URL, test credentials, etc.).
    print_header 3 "Running @app/condo tests with coverage..."
    yarn workspace @app/condo test --coverage --runInBand --forceExit 2>&1 | grep --line-buffered -Fv "${GREP_ARGS[@]}" || true
    CONDO_TEST_EXIT=${PIPESTATUS[0]}
    bash /coverage_reloaded/find-and-move-lcov.sh "unit-condo" "true" "$CONDO_TEST_EXIT"

    # Run other workspace tests with foreach (keeps CWD at root, but other apps
    # don't need apps/condo/.env — they have simple unit tests).
    print_header 3 "Running other workspace tests with coverage..."
    yarn workspaces foreach --exclude @app/condo run test --coverage --runInBand --forceExit 2>&1 | grep --line-buffered -Fv "${GREP_ARGS[@]}" || true
    OTHER_TEST_EXIT=${PIPESTATUS[0]}
    bash /coverage_reloaded/find-and-move-lcov.sh "unit-other" "true" "$OTHER_TEST_EXIT"

    # Propagate failure if either test suite failed
    if [ "$CONDO_TEST_EXIT" -ne 0 ] || [ "$OTHER_TEST_EXIT" -ne 0 ]; then
        TEST_EXIT=1
    else
        TEST_EXIT=0
    fi
else
    # Older eras without workspaces foreach — run all tests together.
    # @open-condo/config won't load apps/condo/.env (CWD is repo root), but
    # these older commits may not have the same dependency on it.
    print_header 3 "Running all workspace tests with coverage..."
    yarn workspaces run test --coverage --runInBand --forceExit 2>&1 | grep --line-buffered -Fv "${GREP_ARGS[@]}" || true
    TEST_EXIT=${PIPESTATUS[0]}
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "true" "$TEST_EXIT"
fi
set -e

# ── Stop the Keystone server ────────────────────────────────────────────────
print_header 3 "Stopping Keystone server..."
set +e
kill $KEYSTONE_PID
# The server may spawn child processes (e.g. worker threads) that don't get
# SIGTERM from the parent kill. Use pkill as a fallback to catch the whole
# node process tree.
pkill -P $KEYSTONE_PID
kill -9 $KEYSTONE_PID
wait $KEYSTONE_PID
set -e

# ── Stop Docker containers ──────────────────────────────────────────────────
print_header 3 "Stopping docker compose services..."
set +e
docker compose down --volumes
set -e

print_header 3 "Stopping Docker daemon..."
set +e
kill $DOCKERD_PID
wait $DOCKERD_PID
set -e

print_header 1 "condo coverage run complete"