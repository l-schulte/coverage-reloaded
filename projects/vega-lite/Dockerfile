ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

# canvas (node-canvas) build deps — prebuilt binaries return 404 for our node
# versions, forcing source compilation via node-gyp which needs these
# pkg-config packages (binding.gyp checks for all three).
RUN apt-get update && apt-get install -y \
      pkg-config \
      libcairo2-dev \
      libpango1.0-dev \
      libpixman-1-dev \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
