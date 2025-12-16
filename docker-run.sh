# !/bin/bash
# $1: directory name (also used as docker image tag)
# $2: mode (test, debug, or exec for full run)
# $3: revision
# $4: timestamp
# $5: package manager, including version (e.g., "npm:16", "yarn:18", "pnpm:20")
# $6: node version for base image (e.g., "node:16")

echo "Script called as: $0 $@"

docker build --build-arg BASE_IMAGE=$6 -t cov_"$1"_"$6" ./projects/$1 
mkdir -p projects/$1/coverage
mkdir -p projects/$1/debug
mkdir -p projects/$1/tmp

if [ "$2" = "test" ]; then
    # Run an interactive container for testing, executes bash on start
    docker run --rm -it --network mining-net --cap-add=NET_ADMIN --env-file .env -v "$(pwd)/projects/$1/coverage:/app/coverage" -e "revision=$3" -e "timestamp=$4" -e "package_manager=$5" cov_"$1"_"$6" bash
elif [ "$2" = "debug" ]; then
    # Run an interactive container for debugging, executes bash and mounts the debug folder
    docker run --rm -it --network mining-net --cap-add=NET_ADMIN --env-file .env -v "$(pwd)/projects/$1/coverage:/app/coverage" -v "$(pwd)/projects/$1/debug:/app" -e "revision=$3" -e "timestamp=$4" -e "package_manager=$5" cov_"$1"_"$6" bash
elif [ "$2" = "exec" ]; then
    # Run the full process non-interactively
    docker run --rm --network mining-net --cap-add=NET_ADMIN --env-file .env -v "$(pwd)/projects/$1/coverage:/app/coverage" -e "revision=$3" -e "timestamp=$4" -e "package_manager=$5" cov_"$1"_"$6" bash run-coverage.sh
fi