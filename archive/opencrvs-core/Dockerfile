ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base
LABEL dind.project="true"

WORKDIR /coverage_reloaded

# Docker-in-Docker: both packages/search and packages/events use testcontainers
# to spin up real Elasticsearch 8.16.4 containers during tests.
RUN apt-get update && apt-get install -y docker.io && rm -rf /var/lib/apt/lists/*

# Prebuilt @rollup/rollup-linux-x64-gnu (pulled by vitest >= 2 out-of-tree coverage provider)
# requires GLIBC 2.32; bullseye base ships 2.31. Pull libc from bookworm (2.36) while
# keeping the rest of the image on bullseye. Same pattern as projects/desktop and projects/sequelize.
RUN echo 'deb http://deb.debian.org/debian bookworm main' > /etc/apt/sources.list.d/bookworm.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends -t bookworm \
         libc6 libc6-dev libc-bin libstdc++6 libgcc-s1 \
    && rm -rf /var/lib/apt/lists/* \
    && ldd --version | head -1

# Pre-stage MongoDB 7.0.14 mongod binary for mongodb-memory-server (used in packages/events and packages/config).
# Bypasses runtime network downloads through Waypack proxy which fail under high worker concurrency.
RUN curl -fsSL https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-debian11-7.0.14.tgz \
    | tar -xz -C /usr/local/bin --strip-components=2 mongodb-linux-x86_64-debian11-7.0.14/bin/mongod \
    && chmod +x /usr/local/bin/mongod \
    && mongod --version | head -n 1

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
COPY ./patch-coverage.js /coverage_reloaded/patch-coverage.js
RUN chmod +x /coverage_reloaded/install-and-run.sh
