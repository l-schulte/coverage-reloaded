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
    suite_start "unit" "Running test suite with coverage"

    set +e
    if [ "$TEST_RUNNER" = "jest" ]; then
        $C8 $PM_RUN test -- --runInBand
    else
        $C8 $PM_RUN test
    fi
    TEST_EXIT=$?
    set -e

    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"
    suite_end "unit" "$TEST_EXIT"
else
    print_header 4 "NOTICE: No test script found"
fi

# --- test:all (slow tests, merges coverage) ---
if [ -n "$TEST_ALL_SCRIPT" ] && [ "$TEST_ALL_SCRIPT" != "$TEST_SCRIPT" ]; then
    suite_start "unit_slow" "Running test:all suite with coverage"

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

    # Look up the closest substrate release ≤ commit timestamp in the lookup CSV.
    # If found, pull that tagged image, retag as :latest, and remove AlwaysPullPolicy
    # so Docker uses the local cache instead of pulling the latest from Hub.
    LOOKUP_CSV="/coverage_reloaded/substrate_lookup.csv"
    SUBSTRATE_TAG=""
    if [ -f "$LOOKUP_CSV" ]; then
        # Read CSV, find the row with the largest epoch ≤ $timestamp
        # Format: epoch,docker_tag  (empty docker_tag means "use :latest")
        BEST_EPOCH=0
        while IFS=',' read -r epoch tag; do
            # Skip header
            if [ "$epoch" = "epoch" ]; then continue; fi
            # Remove trailing \r from Windows-style line endings
            epoch="${epoch//$'\r'/}"
            tag="${tag//$'\r'/}"
            if [ -n "$epoch" ] && [ "$epoch" -le "$timestamp" ] 2>/dev/null; then
                if [ "$epoch" -gt "$BEST_EPOCH" ]; then
                    BEST_EPOCH="$epoch"
                    SUBSTRATE_TAG="$tag"
                fi
            fi
        done < "$LOOKUP_CSV"
    fi

    if [ -n "$SUBSTRATE_TAG" ]; then
        print_header 4 "Pulling parity/substrate:${SUBSTRATE_TAG} (matched at epoch ${BEST_EPOCH}) and retagging as :latest..."
        docker pull "parity/substrate:${SUBSTRATE_TAG}"
        docker tag "parity/substrate:${SUBSTRATE_TAG}" "parity/substrate:latest"
        if [ -f jest/globalSetup.cjs ]; then
            sed -i '/\.withPullPolicy(new AlwaysPullPolicy())/d' jest/globalSetup.cjs
        fi
        if [ -f jest/globalSetup.ts ]; then
            sed -i '/\.withPullPolicy(new AlwaysPullPolicy())/d' jest/globalSetup.ts
        fi
        # NOTE: Likely not needed, since change of parameters was only implemented March 3rd 2023 (71d749c74e43c7a840c94fcbbdd2b0172a21d473)
        #       which is after the last lookup entry in substrate_lookup.csv (2023-02-28 00:00:00 UTC, 1677542400).
        # Patch CLI flags only for 3.0.0-dev images (which renamed --ws-port / --unsafe-ws-external
        # to --rpc-port / --unsafe-rpc-external). Older 2.0.0 images use the original flag names.
        # if echo "$SUBSTRATE_TAG" | grep -q "^3.0.0-dev"; then
        #     print_header 4 "Patching CLI flags for 3.0.0-dev substrate image..."
        #     if [ -f jest/globalSetup.cjs ]; then
        #         cp jest/globalSetup.cjs jest/globalSetup.cjs.bak
        #         sed -i 's/--ws-port=9944/--rpc-port=9944/g; s/--unsafe-ws-external/--unsafe-rpc-external/g' jest/globalSetup.cjs
        #     fi
        #     if [ -f jest/globalSetup.ts ]; then
        #         cp jest/globalSetup.ts jest/globalSetup.ts.bak
        #         sed -i 's/--ws-port=9944/--rpc-port=9944/g; s/--unsafe-ws-external/--unsafe-rpc-external/g' jest/globalSetup.ts
        #     fi
        # fi
    else
        print_header 4 "No substrate release found ≤ timestamp $timestamp. PANIC!"
        # This should not happen, oldest substrate release in lookup CSV is 2.0.0-c6fc2e6 at epoch 1576247273 (2019-12-13 00:01:13 UTC)
        exit 1
    fi

    print_header 3 "Running test:all suite with coverage"

    set +e
    $C8 $PM_RUN test:all
    TEST_ALL_EXIT=$?
    set -e

    bash /coverage_reloaded/find-and-move-lcov.sh "unit_slow" "false" "$TEST_ALL_EXIT"
    suite_end "unit_slow" "$TEST_ALL_EXIT"

    # Clean up the timestamp proxy
    kill $PROXY_PID 2>/dev/null || true
fi

print_header 1 "Polkadot Apps coverage run complete"