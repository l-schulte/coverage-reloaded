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

if $IS_YARN_MAIN_PM; then
    yarn install | grep -v "warning @polkadot"
    PM_RUN="yarn run"
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

print_header 2 "Detecting test scripts"

TEST_SCRIPT=$(node -p "p=require('./package.json').scripts; (p.test || '')")
TEST_ALL_SCRIPT=$(node -p "p=require('./package.json').scripts; (p['test:all'] || '')")

print_header 4 "test:       $TEST_SCRIPT"
print_header 4 "test:all:   $TEST_ALL_SCRIPT"

# Handle "skipping tests" eras — no tests to run
if echo "$TEST_SCRIPT" | grep -qE '^echo "skipping tests"$|^echo '"'"'tests skipped'"'"'$'; then
    print_header 2 "NOT APPLICABLE" "Tests are skipped at this commit"
    exit 2
fi

# Determine if this is a jest-based or polkadot-dev-run-test-based test script
if echo "$TEST_SCRIPT" | grep -q "^jest "; then
    print_header 2 "Detected Jest-based test script" "Command: $TEST_SCRIPT"
    TEST_RUNNER="jest"
else
    print_header 2 "Detected polkadot-dev-run-test-based test script" "Command: $TEST_SCRIPT"
    TEST_RUNNER="polkadot"
fi

print_header 2 "Running tests with coverage ($TEST_RUNNER)"

# c8 base command — use Verdaccio (live registry) for our own tooling,
# not WayPack (which is timestamp-scoped to the commit).
if [ "$TEST_RUNNER" = "jest" ]; then
    C8="npx --registry=$VERDACCIO_REGISTRY c8 --reporter=lcov"
else
    C8="taskset -c 0 npx --registry=$VERDACCIO_REGISTRY c8 --reporter=lcov"
fi

# --- test ---
if [ -n "$TEST_SCRIPT" ]; then
    print_header 3 "Running test suite"

    set +e
    if [ "$TEST_RUNNER" = "jest" ]; then
        $C8 $PM_RUN test -- --runInBand
    else
        $C8 $PM_RUN test
    fi
    TEST_EXIT=$?
    set -e

    print_header 4 "test exit code: $TEST_EXIT"
    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"
else
    print_header 4 "NOTICE: No test script found"
fi

# --- test:all (slow tests, merges coverage) ---
if [ -n "$TEST_ALL_SCRIPT" ] && [ "$TEST_ALL_SCRIPT" != "$TEST_SCRIPT" ]; then
    print_header 3 "Running test:all suite"

    # The test:all suite uses testcontainers to spin up a parity/substrate
    # Docker container. Start the Docker daemon (DinD with --privileged) and
    # verify it's reachable before running.
    # Configure dockerd to use the docker-cache registry mirror on the mining-net
    # network. This avoids rate limits and speeds up pulls for the Substrate image.
    print_header 4 "Starting Docker daemon..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": ["http://docker-cache:5000"],
  "insecure-registries": ["http://docker-cache:5000"],
  "dns": ["1.1.1.1", "8.8.8.8"]
}
EOF
    dockerd > /var/log/dockerd.log 2>&1 &
    DOCKERD_PID=$!
    # Wait up to 30s for the daemon to be ready
    for i in $(seq 1 30); do
        if docker ps > /dev/null 2>&1; then
            print_header 4 "Docker daemon ready (attempt $i)"
            break
        fi
        sleep 1
    done
    if ! docker ps > /dev/null 2>&1; then
        print_header 2 "DOCKER DAEMON FAILED" "Could not start Docker daemon. Check /var/log/dockerd.log for details."
        cat /var/log/dockerd.log
        exit 1
    fi

    # Patch globalSetup.cjs to use the current parity/substrate CLI flags.
    # The image was updated and --ws-port / --unsafe-ws-external were renamed
    # to --rpc-port / --unsafe-rpc-external.
    if [ -f jest/globalSetup.cjs ]; then
        print_header 4 "Patching jest/globalSetup.cjs for parity/substrate CLI changes..."
        sed -i 's/--ws-port=9944/--rpc-port=9944/g; s/--unsafe-ws-external/--unsafe-rpc-external/g' jest/globalSetup.cjs
    fi

    print_header 3 "Running test:all suite with coverage"

    set +e
    $C8 $PM_RUN test:all
    TEST_ALL_EXIT=$?
    set -e

    print_header 4 "test:all exit code: $TEST_ALL_EXIT"
    bash /coverage_reloaded/find-and-move-lcov.sh "unit_slow" "false" "$TEST_ALL_EXIT"

    # Clean up the timestamp proxy
    kill $PROXY_PID 2>/dev/null || true
fi

print_header 1 "Polkadot Apps coverage run complete"