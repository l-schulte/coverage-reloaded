ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

# Symlink sh to bash so postinstall.sh works (macOS uses bash as sh, which supports [[)
RUN ln -sf /bin/bash /bin/sh

# Install libudev-dev + libusb-1.0-0 + libusb-1.0-0-dev so node-hid can compile
RUN apt-get update && apt-get install -y libudev-dev libusb-1.0-0 libusb-1.0-0-dev

WORKDIR /coverage_reloaded

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
