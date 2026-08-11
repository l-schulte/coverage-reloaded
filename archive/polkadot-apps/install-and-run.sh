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
    yarn install
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
    TEST_RUNNER="jest"
else
    TEST_RUNNER="polkadot"
fi

# Determine the test ERA. The node:test era (newer @polkadot/dev, ~2023+) invokes
# `polkadot-dev-run-test --env …`, which wraps polkadot-exec-node-test.mjs. That
# runner REJECTS jest flags (--runInBand/--coverage/--coverageReporters/--testPathIgnorePatterns)
# and crashes ("Unknown flag --runInBand" / treats them as test files -> EPIPE).
# The jest era uses `jest …` or `polkadot-dev-run-test --selectProjects=…`.
ERA="jest"
if echo "$TEST_SCRIPT" | grep -qE 'polkadot-dev-run-test .*--env |polkadot-exec-node-test'; then
    ERA="node-test"
fi

print_header 2 "Running tests with coverage ($TEST_RUNNER, era=$ERA)"

# --- test ---
if [ -n "$TEST_SCRIPT" ]; then
    suite_start "unit" "Running test suite with coverage"

    set +e
    if [ "$ERA" = "node-test" ]; then
        # node:test era (@polkadot/dev >=0.83) does NOT emit lcov itself — its
        # runner invokes node:test via worker threads and rejects jest flags.
        # @polkadot/dev@0.83 has no c8/coverage wiring, so wrap with c8 (our
        # tooling, via Verdaccio) per AGENTS.md §6 to produce lcov.
        npx --registry=$VERDACCIO_REGISTRY c8 --reporter=lcov $PM_RUN test
        TEST_EXIT=$?
        bash /coverage_reloaded/find-and-move-lcov.sh "unit_polkadot" "false" "$TEST_EXIT"
    elif [ "$TEST_RUNNER" = "jest" ]; then
        $PM_RUN test --runInBand --coverage --coverageReporters=lcov
        TEST_EXIT=$?
        bash /coverage_reloaded/find-and-move-lcov.sh "unit_jest" "false" "$TEST_EXIT"
    else
        $PM_RUN test --runInBand --coverage --coverageReporters=lcov
        TEST_EXIT=$?
        bash /coverage_reloaded/find-and-move-lcov.sh "unit_polkadot" "false" "$TEST_EXIT"
    fi
    set -e
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
    #
    # Which tests actually NEED this local substrate container?
    # Only specs that connect to the local dev chain at
    #   ws://127.0.0.1:<TEST_SUBSTRATE_PORT>
    # via @polkadot/test-support's createApi()
    # (packages/test-support/src/api/createApi.ts -> new WsProvider(`ws://127.0.0.1:${port}`)).
    # At commit a9218a788f6e6a0002ecdbddbcc97dfedfaf06d3 (1626276306) that is
    # e.g. packages/page-bounties/src/helpers/
    # determineUnassignCuratorAction.spec.ts. Those specs would hang/fail
    # without the container.
    #
    # The excluded suites (chainEndpoints/chainTypes/CreateAccount.slow) do
    # NOT use this container: ci/chainTypes.spec.ts -> ci/util.ts dials the
    # LIVE wss:// production endpoints in apps-config/src/endpoints/production.ts.
    # So the substrate container version below only matters for the local-chain
    # specs; the live-endpoint errors are network drift, independent of it.
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

        # Determine the resolved testcontainers version from the lockfile so we only
        # downgrade when actually required. testcontainers 8.17.0 renamed
        # withCmd() → withCommand() and removed the AlwaysPullPolicy class; the
        # project's source still uses the old API. Earlier versions (7.x) already
        # ship that API, and forcing 8.16.0 against the temporal registry fails to
        # resolve ("No candidates found") and corrupts the install — so skip it.
        TC_VERSION=""
        if [ -f yarn.lock ]; then
            TC_VERSION=$(awk '
                /^"?testcontainers@npm:/{found=1; next}
                found && /^[^ ]/ {found=0}
                found && /version:/ {gsub(/[^0-9.]/, "", $2); print $2; exit}
            ' yarn.lock)
        fi

        # Only downgrade when the resolved version is >= 8.17.0 AND the project
        # source still uses the old `withCmd` API. If the source already uses the
        # new `withCommand` API, the installed version is already correct and
        # downgrading would break it.
        USES_OLD_API="false"
        for gs in jest/globalSetup.cjs jest/globalSetup.ts; do
            if [ -f "$gs" ] && grep -q 'withCmd(' "$gs"; then
                USES_OLD_API="true"
            fi
        done

        if [ -n "$TC_VERSION" ] && [ "$(printf '%s\n%s\n' "$TC_VERSION" "8.17.0" | sort -V | head -n1)" = "8.17.0" ] && [ "$USES_OLD_API" = "true" ]; then
            if $IS_YARN_MAIN_PM; then
                print_header 4 "Downgrading testcontainers ${TC_VERSION} -> 8.16.0..."
                yarn up testcontainers@8.16.0 2>&1 | grep -v "warning @polkadot"
            fi
        else
            print_header 4 "testcontainers@${TC_VERSION:-unknown} — no downgrade required (version < 8.17.0 or source uses new withCommand API)"
        fi
        # Remove AlwaysPullPolicy so testcontainers uses the locally cached
        # :latest image instead of trying to pull from the registry again.
        if [ -f jest/globalSetup.cjs ]; then
            print_header 4 "Removing AlwaysPullPolicy from jest/globalSetup.cjs..."
            sed -i '/\.withPullPolicy(new AlwaysPullPolicy())/d' jest/globalSetup.cjs
        fi
        if [ -f jest/globalSetup.ts ]; then
            print_header 4 "Removing AlwaysPullPolicy from jest/globalSetup.ts..."
            sed -i '/\.withPullPolicy(new AlwaysPullPolicy())/d' jest/globalSetup.ts
        fi

    else
        print_header 4 "No substrate release found ≤ timestamp $timestamp. PANIC!"
        # This should not happen, oldest substrate release in lookup CSV is 2.0.0-c6fc2e6 at epoch 1576247273 (2019-12-13 00:01:13 UTC)
        exit 1
    fi

    print_header 3 "Running test:all suite with coverage"

    # Exclude chainEndpoints.spec.ts — it's an infrastructure connectivity check
    # (not a behavioral test) that tries to connect to real WebSocket endpoints
    # which are no longer available. Per AGENT.md §8, exclude suites whose
    # execution exists purely for infrastructure monitoring, not behavioral
    # verification. The project itself later narrowed test:all to only run
    # ^chainEndpoints ^chainTypes (commit 3b60b91, Feb 2023), confirming these
    # are not behavioral tests.
    #
    # Also exclude CreateAccount.slow.spec.tsx — the button label it looks for
    # ("Add account") was changed to "Account" in commit 8fbcbf8d (Jan 2023),
    # but the test was never updated. It fails immediately on findByText and
    # contributes no unique coverage beyond what the fast suite already provides.
    set +e
    if [ "$ERA" = "node-test" ]; then
        # node:test era: run the project's own test:all wrapped with c8 (no c8
        # wiring in @polkadot/dev). Exclude CreateAccount.slow (stale "Add account"
        # label). We do not start the substrate container ourselves here — if
        # local-chain specs need it and it is unavailable, they fail softly and the
        # rest of the suite still produces valid partial coverage (AGENTS.md §7).
        npx --registry=$VERDACCIO_REGISTRY c8 --reporter=lcov $PM_RUN test:all ^CreateAccount.slow
        TEST_ALL_EXIT=$?
    else
        # Force JEST_WORKER_ID so @polkadot/dev's babel-plugin-module-extension-resolver
        # does NOT rewrite relative imports './foo' -> './foo.cjs'. Under --runInBand
        # jest runs in-process and leaves JEST_WORKER_ID unset, which trips the plugin's
        # gate (`!process.env.JEST_WORKER_ID ...`) and mass-breaks test:all with
        # "Cannot find module './Backend.cjs'" (Group 2 failures). Setting it here is
        # inert for jest/@polkadot/dev versions that lack the gate.
        JEST_WORKER_ID=1 $PM_RUN test:all --runInBand --coverage --coverageReporters=lcov --testPathIgnorePatterns 'chainEndpoints|chainTypes|CreateAccount.slow'
        TEST_ALL_EXIT=$?
    fi
    set -e

    bash /coverage_reloaded/find-and-move-lcov.sh "unit_slow" "false" "$TEST_ALL_EXIT"
    suite_end "unit_slow" "$TEST_ALL_EXIT"

    # Clean up the timestamp proxy
    kill $PROXY_PID 2>/dev/null || true
fi

print_header 1 "Polkadot Apps coverage run complete"