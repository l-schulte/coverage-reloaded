ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

# some versions of polkadot need extra dependencies, otherwise gyp fails

RUN apt-get update && \
    apt-get install -y \
        pkg-config \
        libusb-1.0

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh