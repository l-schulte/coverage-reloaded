ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

# Install libudev-dev + libusb-1.0-0 so node-hid (used by @ledgerhq/hw-transport-node-hid) can compile
RUN apt-get update && apt-get install -y libudev-dev libusb-1.0-0

WORKDIR /coverage_reloaded

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
