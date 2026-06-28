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
echo "bash $(basename "$0") $* 2>&1 | tee projects/$1/logs/${4}_${3}_\$(date +\"%Y%m%d_%H%M%S\").log"
echo ""

# Change to "docker" if necessary
EXECUTOR="podman"

BASE_CONTAINER_NAME=core_node"$6"_base
PROJECT_TAG=$(echo "$1" | tr '[:upper:]' '[:lower:]')
CONTAINER_NAME=core_node"$6"_"$PROJECT_TAG"
CONTAINER_DIR=/coverage_reloaded

ENV_CONFIG="--env-file .env --env revision=$3 --env timestamp=$4 --env package_manager=$5 --env project_id=$7"
DNS_CONFIG="--dns 1.1.1.1 --dns 8.8.8.8"

$EXECUTOR build --build-arg NODE_VERSION=$6 -t $BASE_CONTAINER_NAME .

$EXECUTOR build --build-arg NODE_VERSION=$6 -t $CONTAINER_NAME ./projects/$1 

# if ! $EXECUTOR image exists $BASE_CONTAINER_NAME; then
#     flock /tmp/lock-$BASE_CONTAINER_NAME.lock \
#         sh -c "! $EXECUTOR image exists $BASE_CONTAINER_NAME && \
#                $EXECUTOR build --build-arg NODE_VERSION=$6 -t $BASE_CONTAINER_NAME ."
# fi

# if ! $EXECUTOR image exists $CONTAINER_NAME; then
#     flock /tmp/lock-$CONTAINER_NAME.lock \
#         sh -c "! $EXECUTOR image exists $CONTAINER_NAME && \
#                $EXECUTOR build --build-arg NODE_VERSION=$6 -t $CONTAINER_NAME ./projects/$1"
# fi

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
    $EXECUTOR run --rm -it --network mining-net --cap-add=NET_ADMIN $ENV_CONFIG $DNS_CONFIG $EXTRA_FLAGS -v "$(pwd)/projects/$1/output:$CONTAINER_DIR/coverage" --pids-limit 10000 $CONTAINER_NAME bash
elif [ "$2" = "debug" ]; then
    # Run an interactive container for debugging, executes bash and mounts the debug folder
    mkdir -p projects/$1/debug
    $EXECUTOR run --rm -it --network mining-net --cap-add=NET_ADMIN $ENV_CONFIG $DNS_CONFIG $EXTRA_FLAGS -v "$(pwd)/projects/$1/output:$CONTAINER_DIR/coverage" -v "$(pwd)/projects/$1/debug:$CONTAINER_DIR" --pids-limit 10000 $CONTAINER_NAME bash
elif [ "$2" = "exec" ]; then
    # Run the full process non-interactively
    $EXECUTOR run --rm --network mining-net --cap-add=NET_ADMIN $ENV_CONFIG $DNS_CONFIG $EXTRA_FLAGS -v "$(pwd)/projects/$1/output:$CONTAINER_DIR/coverage" --pids-limit 10000 $CONTAINER_NAME bash execute.sh
fi