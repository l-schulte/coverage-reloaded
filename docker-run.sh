# !/bin/bash
# $1: directory name (also used as docker image tag)
# $2: mode (shell, debug, or exec for full run)
# $3: revision
# $4: timestamp
# $5: package manager, including version (e.g., "npm:16", "yarn:18", "pnpm:20")
# $6: node version for base image (e.g., "16")
# $7: (optional) project_id to use inside the container, e.g., for reporting to coverageSHARK

echo "Script called as:"
echo "bash $(basename "$0") $*"
echo ""
echo "Rerun with:"
echo "bash $(basename "$0") $* 2>&1 | tee >(strip-ansi > projects/$1/logs/${4}_${3}_\$(date +\"%Y%m%d_%H%M%S\").log)"
echo ""

# Change to "docker" if necessary
EXECUTOR="podman"

BASE_CONTAINER_NAME=core_node"$6"_base
PROJECT_TAG=$(echo "$1" | tr '[:upper:]' '[:lower:]')
CONTAINER_NAME=core_node"$6"_"$PROJECT_TAG"
CONTAINER_DIR=/coverage_reloaded

# The repo is served from an in-memory tmpfs (see execute.sh). Declared at
# runtime because the container lacks CAP_SYS_ADMIN and cannot mount tmpfs
# itself; --tmpfs needs no extra capabilities. Default 35g accommodates large
# historical monorepos before workspaces (e.g. compass in mid-2021 with 78
# independent package trees).
TMPFS_SIZE=${TMPFS_SIZE:-35g}

# USE_TMPFS=false opts out of the in-memory repo mount and runs the repo on
# the container's writable-layer disk instead — for low-RAM hosts (e.g. 16 GB)
# where a large tmpfs ceiling would compete with the test run for memory.
# The flag must be exported in the invoking shell (docker_run.py copies the
# host env); it is NOT read from .env, which is only passed into the container.
USE_TMPFS=${USE_TMPFS:-true}
if [ "$USE_TMPFS" = "true" ]; then
    TMPFS_CONFIG="--tmpfs /coverage_reloaded/repo:rw,size=$TMPFS_SIZE"
else
    echo "NOTICE: USE_TMPFS=false — running /coverage_reloaded/repo on container disk (no tmpfs)"
    TMPFS_CONFIG=""
fi

# use_tmpfs tells execute.sh whether the tmpfs opt-out above was intentional,
# so it can distinguish a deliberate disk run from a misconfigured runtime.
ENV_CONFIG="--env-file .env --env revision=$3 --env timestamp=$4 --env package_manager=$5 --env project_id=$7 --env use_tmpfs=$USE_TMPFS"

# CONTAINER_CPUS caps the CPU *quota* the container may consume (N CPU-seconds
# per real second), i.e. it throttles aggregate CPU time — it does NOT change
# the number of cores the container SEES via os.cpus()/nproc. That's fine: a
# 264-core host running many containers in parallel is bounded by the quota per
# container, and the actual worker parallelism is capped explicitly in
# install-and-run.sh (--maxWorkers=1 / --runInBand, per AGENTS.md §7.1), not by
# core-count detection. docker_run.py sets this to 4; default 20 for manual runs.
CONTAINER_CPUS=${CONTAINER_CPUS:-20}
CPU_CONFIG="--cpus=$CONTAINER_CPUS"

# When SKIP_BUILD is set (e.g. from docker_run.py), images were already
# pre-built — skip redundant rebuilds.  Manual CLI invocations never set
# this, so builds always happen in shell/debug/exec mode.
if [ "${SKIP_BUILD:-false}" != "true" ]; then
    $EXECUTOR build --build-arg NODE_VERSION=$6 -t $BASE_CONTAINER_NAME .
    $EXECUTOR build --build-arg NODE_VERSION=$6 -t $CONTAINER_NAME ./projects/$1
fi

mkdir -p projects/$1/output

# Some projects (e.g. condo) need Docker-in-Docker for their docker-compose-based
# test infrastructure (postgresdb, redis). Add --privileged when the project's
# Dockerfile sets the DIND_PROJECT label.
DIND=$($EXECUTOR image inspect $CONTAINER_NAME --format '{{ index .Config.Labels "dind.project" }}' 2>/dev/null || echo "")
if [ "$DIND" = "true" ]; then
    EXTRA_FLAGS="--privileged"
else
    EXTRA_FLAGS=""
fi

if [ "$2" = "shell" ]; then
    # Run an interactive container for testing, executes bash on start
    $EXECUTOR run --rm -it --network mining-net --cap-add=NET_ADMIN $ENV_CONFIG $CPU_CONFIG $TMPFS_CONFIG $EXTRA_FLAGS -v "$(pwd)/projects/$1/output:$CONTAINER_DIR/coverage" --pids-limit 10000 $CONTAINER_NAME bash
elif [ "$2" = "debug" ]; then
    # Run an interactive container for debugging, executes bash and mounts the debug folder
    mkdir -p projects/$1/debug
    $EXECUTOR run --rm -it --network mining-net --cap-add=NET_ADMIN $ENV_CONFIG $CPU_CONFIG $TMPFS_CONFIG $EXTRA_FLAGS -v "$(pwd)/projects/$1/output:$CONTAINER_DIR/coverage" -v "$(pwd)/projects/$1/debug:$CONTAINER_DIR" --pids-limit 10000 $CONTAINER_NAME bash
elif [ "$2" = "exec" ]; then
    # Run the full process non-interactively
    $EXECUTOR run --rm --network mining-net --cap-add=NET_ADMIN $ENV_CONFIG $CPU_CONFIG $TMPFS_CONFIG $EXTRA_FLAGS -v "$(pwd)/projects/$1/output:$CONTAINER_DIR/coverage" --pids-limit 10000 $CONTAINER_NAME bash execute.sh
fi