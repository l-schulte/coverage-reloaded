# !/bin/bash
# $1: directory name (also used as docker image tag)
# $2: mode (shell, debug, or exec for full run)
# $3: revision
# $4: timestamp
# $5: package manager, including version (e.g., "npm:16", "yarn:18", "pnpm:20")
# $6: node version for base image (e.g., "16")
# $7: (optional) project_id to use inside the container, e.g., for reporting to coverageSHARK

echo "Script called as: $0 $@"

cp execute.sh projects/$1/
cp find-and-move-lcov.sh projects/$1/

docker build --build-arg NODE_VERSION=$6 -t cov_"$1"_node"$6" ./projects/$1 
docker volume create cov_"$1"_data

mkdir -p projects/$1/output
mkdir -p projects/$1/debug

if [ "$2" = "shell" ]; then
    # Run an interactive container for testing, executes bash on start
    docker run --rm -it --network mining-net --cap-add=NET_ADMIN --env-file .env -v "$(pwd)/projects/$1/output:/app/coverage" -v cov_"$1"_data:/app/data -e "revision=$3" -e "timestamp=$4" -e "package_manager=$5" -e "project_id=$7" cov_"$1"_node"$6" bash
elif [ "$2" = "debug" ]; then
    # Run an interactive container for debugging, executes bash and mounts the debug folder
    docker run --rm -it --network mining-net --cap-add=NET_ADMIN --env-file .env -v "$(pwd)/projects/$1/output:/app/coverage" -v "$(pwd)/projects/$1/debug:/app" -v cov_"$1"_data:/app/data -e "revision=$3" -e "timestamp=$4" -e "package_manager=$5" -e "project_id=$7" cov_"$1"_node"$6" bash
elif [ "$2" = "exec" ]; then
    # Run the full process non-interactively
    docker run --rm --network mining-net --cap-add=NET_ADMIN --env-file .env -v "$(pwd)/projects/$1/output:/app/coverage" -v cov_"$1"_data:/app/data -e "revision=$3" -e "timestamp=$4" -e "package_manager=$5" -e "project_id=$7" cov_"$1"_node"$6" bash execute.sh
fi