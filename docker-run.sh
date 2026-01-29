# !/bin/bash
# $1: directory name (also used as docker image tag)
# $2: mode (shell, debug, or exec for full run)
# $3: revision
# $4: timestamp
# $5: package manager, including version (e.g., "npm:16", "yarn:18", "pnpm:20")
# $6: node version for base image (e.g., "16")
# $7: (optional) project_id to use inside the container, e.g., for reporting to coverageSHARK

echo "Script called as: $0 $@"

docker build --build-arg NODE_VERSION=$6 -t core_node"$6"_base .

docker build --build-arg NODE_VERSION=$6 -t core_node"$6"_"$1" ./projects/$1 
docker volume create core_"$1"_data

mkdir -p projects/$1/output

if [ "$2" = "shell" ]; then
    # Run an interactive container for testing, executes bash on start
    docker run --rm -it --network mining-net --cap-add=NET_ADMIN --env-file .env -v "$(pwd)/projects/$1/output:/app/coverage" -v core_"$1"_data:/app/data -e "revision=$3" -e "timestamp=$4" -e "package_manager=$5" -e "project_id=$7" core_node"$6"_"$1" bash
elif [ "$2" = "debug" ]; then
    # Run an interactive container for debugging, executes bash and mounts the debug folder
    mkdir -p projects/$1/debug
    docker run --rm -it --network mining-net --cap-add=NET_ADMIN --env-file .env -v "$(pwd)/projects/$1/output:/app/coverage" -v "$(pwd)/projects/$1/debug:/app" -v core_"$1"_data:/app/data -e "revision=$3" -e "timestamp=$4" -e "package_manager=$5" -e "project_id=$7" core_node"$6"_"$1" bash
elif [ "$2" = "exec" ]; then
    # Run the full process non-interactively
    docker run --rm --network mining-net --cap-add=NET_ADMIN --env-file .env -v "$(pwd)/projects/$1/output:/app/coverage" -v core_"$1"_data:/app/data -e "revision=$3" -e "timestamp=$4" -e "package_manager=$5" -e "project_id=$7" core_node"$6"_"$1" bash execute.sh
fi