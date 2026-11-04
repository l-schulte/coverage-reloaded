ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

# docker-run.sh turns this label into --privileged so a nested dockerd can run.
# data-service's connectivity integration suite (only 2021-08-26 .. 2021-10-11) starts a
# mongod through docker-compose; install-and-run.sh starts the daemon only for commits
# that still contain that spec.
LABEL dind.project="true"

WORKDIR /coverage_reloaded

RUN echo 'deb http://deb.debian.org/debian bookworm main' > /etc/apt/sources.list.d/bookworm.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends -t bookworm \
    libkrb5-dev \
    libsecret-1-dev \
    net-tools \
    gnome-keyring \
    xvfb \
    libnotify-dev \
    libssl3 \
    libmongocrypt-dev \
    libnss3 \
    libasound2 \
    libxtst6 \
    libxss1 \
    libgtk-3-0 \
    libgdk-pixbuf2.0-0 \
    libpango-1.0-0 \
    libgbm1 \
    libxshmfence1 \
    docker.io \
    docker-compose \
    && rm -rf /var/lib/apt/lists/*

# Install libssl1.1 alongside libssl3 so legacy Debian 10/11 MongoDB binaries run on Debian 12
RUN curl -fsSL http://ftp.debian.org/debian/pool/main/o/openssl/libssl1.1_1.1.1w-0+deb11u1_amd64.deb -o /tmp/libssl1.1.deb \
    && dpkg -i /tmp/libssl1.1.deb \
    && rm /tmp/libssl1.1.deb

# Pre-cache era-specific MongoDB binaries in /opt/mongodb/<version>/bin/{mongod,mongos}
# mongos is required by mongodb-runner's sharded topology (added upstream 2025-11-10,
# packages/data-service "with real sharded cluster"). Without it, MongoServer.start()
# spawns <binDir>/mongos, gets ENOENT and then throws
# "TypeError: Cannot read properties of undefined (reading 'some')" from its own
# error handler (err.errorLogEntries is undefined for a spawn failure).
RUN mkdir -p /opt/mongodb/4.4/bin && \
    curl -fsSL https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-debian10-4.4.29.tgz -o /tmp/mongo-4.4.tgz && \
    tar -xzf /tmp/mongo-4.4.tgz --strip-components=2 -C /opt/mongodb/4.4/bin mongodb-linux-x86_64-debian10-4.4.29/bin/mongod mongodb-linux-x86_64-debian10-4.4.29/bin/mongos && \
    chmod +x /opt/mongodb/4.4/bin/mongod /opt/mongodb/4.4/bin/mongos && rm /tmp/mongo-4.4.tgz

RUN mkdir -p /opt/mongodb/5.0/bin && \
    curl -fsSL https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-debian11-5.0.28.tgz -o /tmp/mongo-5.0.tgz && \
    tar -xzf /tmp/mongo-5.0.tgz --strip-components=2 -C /opt/mongodb/5.0/bin mongodb-linux-x86_64-debian11-5.0.28/bin/mongod mongodb-linux-x86_64-debian11-5.0.28/bin/mongos && \
    chmod +x /opt/mongodb/5.0/bin/mongod /opt/mongodb/5.0/bin/mongos && rm /tmp/mongo-5.0.tgz

RUN mkdir -p /opt/mongodb/6.0/bin && \
    curl -fsSL https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-debian11-6.0.20.tgz -o /tmp/mongo-6.0.tgz && \
    tar -xzf /tmp/mongo-6.0.tgz --strip-components=2 -C /opt/mongodb/6.0/bin mongodb-linux-x86_64-debian11-6.0.20/bin/mongod mongodb-linux-x86_64-debian11-6.0.20/bin/mongos && \
    chmod +x /opt/mongodb/6.0/bin/mongod /opt/mongodb/6.0/bin/mongos && rm /tmp/mongo-6.0.tgz

RUN mkdir -p /opt/mongodb/7.0/bin && \
    curl -fsSL https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-debian11-7.0.14.tgz -o /tmp/mongo-7.0.tgz && \
    tar -xzf /tmp/mongo-7.0.tgz --strip-components=2 -C /opt/mongodb/7.0/bin mongodb-linux-x86_64-debian11-7.0.14/bin/mongod mongodb-linux-x86_64-debian11-7.0.14/bin/mongos && \
    chmod +x /opt/mongodb/7.0/bin/mongod /opt/mongodb/7.0/bin/mongos && rm /tmp/mongo-7.0.tgz

RUN mkdir -p /opt/mongodb/8.0/bin && \
    curl -fsSL https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-debian12-8.0.4.tgz -o /tmp/mongo-8.0.tgz && \
    tar -xzf /tmp/mongo-8.0.tgz --strip-components=2 -C /opt/mongodb/8.0/bin mongodb-linux-x86_64-debian12-8.0.4/bin/mongod mongodb-linux-x86_64-debian12-8.0.4/bin/mongos && \
    chmod +x /opt/mongodb/8.0/bin/mongod /opt/mongodb/8.0/bin/mongos && rm /tmp/mongo-8.0.tgz && \
    ln -sf /opt/mongodb/8.0/bin/mongod /usr/local/bin/mongod && \
    ln -sf /opt/mongodb/8.0/bin/mongos /usr/local/bin/mongos

# mongodb-download-url inspects /etc/os-release to determine the distribution target.
# Setting VERSION_ID="12" allows it to resolve official Debian 12 binaries (required for MongoDB 8.0+)
# while maintaining backwards-compatible fallbacks for debian11/debian10 (MongoDB 4.x-7.x).
RUN printf '%s\n' \
    'PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"' \
    'NAME="Debian GNU/Linux"' \
    'VERSION_ID="12"' \
    'VERSION="12 (bookworm)"' \
    'VERSION_CODENAME=bookworm' \
    'ID=debian' \
    > /etc/os-release

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
COPY ./patch-coverage.js /coverage_reloaded/patch-coverage.js
RUN chmod +x /coverage_reloaded/install-and-run.sh
