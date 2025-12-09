# !/bin/bash
# $1: directory name (also used as docker image tag)
# $2: mode (test, debug, or exec for full run)
# $3: revision
# $4: timestamp

echo "Building and running Docker container for $1 in mode '$2' with revision '$3' and timestamp '$4'"
docker build -t cov_"$1" ./$1 
mkdir -p $1/coverage
mkdir -p $1/debug
mkdir -p $1/tmp

cp ./go-waypack.sh ./$1/tmp/go-waypack.sh
sleep 3

if [ "$2" = "test" ]; then
    # Run an interactive container for testing, executes bash on start
    docker run --rm -it --network mining-net --cap-add=NET_ADMIN --env-file .env -v "$(pwd)/$1/coverage:/app/coverage" -e "revision=$3" -e "timestamp=$4" cov_"$1" bash
elif [ "$2" = "debug" ]; then
    # Run an interactive container for debugging, executes bash and mounts the debug folder
    docker run --rm -it --network mining-net --cap-add=NET_ADMIN --env-file .env -v "$(pwd)/$1/coverage:/app/coverage" -v "$(pwd)/$1/debug:/workspace" -e "revision=$3" -e "timestamp=$4" cov_"$1" bash
elif [ "$2" = "exec" ]; then
    # Run the full process non-interactively
    docker run --rm --network mining-net --cap-add=NET_ADMIN --env-file .env -v "$(pwd)/$1/coverage:/app/coverage" -e "revision=$3" -e "timestamp=$4" cov_"$1" bash go-waypack.sh
fi