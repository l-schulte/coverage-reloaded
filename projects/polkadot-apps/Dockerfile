ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base
LABEL dind.project="true"

WORKDIR /coverage_reloaded

# some versions of polkadot need extra dependencies, otherwise gyp fails

RUN apt-get update && \
    apt-get install -y \
        pkg-config \
        libusb-1.0

# Install Docker daemon for Docker-in-Docker.
# The slow test suite (test:all) uses the testcontainers Node.js library to
# spin up a parity/substrate container for integration tests. This requires
# a working Docker daemon inside the container.
RUN apt-get update && apt-get install -y docker.io

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh