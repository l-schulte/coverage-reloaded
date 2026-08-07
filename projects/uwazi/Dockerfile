ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

# Uwazi tests need Elasticsearch, which we run via Docker-in-Docker using the
# project's own elastic-icu-*.Dockerfile (docker-run.sh turns this label into
# --privileged, same as rxdb/polkadot-apps).
LABEL dind.project="true"

WORKDIR /coverage_reloaded

# Uwazi tests need MongoDB (for DB-backed integration tests) and Redis (for
# socket.io pub/sub and session caching).  mongodb-memory-server was used in
# early commits but was removed after the Node 16.17 upgrade (Aug 2022), after
# which tests connect to a real mongod at localhost:27017 (as a replica set).
# Redis is used by setUpJestServer.js for socket.io infrastructure.
#
# Debian bullseye does not ship mongod in its default repos, so we add the
# official MongoDB 7.0 repo (matches the project's own CI runner image).
# mongodb-mongosh is installed explicitly for the replica-set bootstrap.
#
# docker.io provides dockerd/docker so install-and-run.sh can run Elasticsearch
# in a nested container (via docker-run.sh's --privileged).
RUN apt-get update && apt-get install -y gnupg --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc \
       | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg \
    && echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/debian bullseye/mongodb-org/7.0 main" \
       > /etc/apt/sources.list.d/mongodb-org-7.0.list \
    && apt-get update && apt-get install -y \
      mongodb-org \
      mongodb-mongosh \
      redis-server \
      libpng-dev \
      poppler-utils \
      libjpeg-dev \
      docker.io \
      --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# mongodb-memory-server (used by tests until Aug 2022) is pointed at this binary
# via MONGOMS_SYSTEM_BINARY.  MongoDB 4.4 is the version those memory-server
# versions expect; the debian10 build runs on bullseye (links libssl1.1).
RUN curl -fsSL https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-debian10-4.4.8.tgz -o /tmp/mongodb-4.4.8.tgz \
    && tar -xzf /tmp/mongodb-4.4.8.tgz --strip-components=2 -C /usr/local/bin mongodb-linux-x86_64-debian10-4.4.8/bin/mongod \
    && mv /usr/local/bin/mongod /usr/local/bin/mongod-4.4.8 \
    && chmod +x /usr/local/bin/mongod-4.4.8 \
    && rm /tmp/mongodb-4.4.8.tgz

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
