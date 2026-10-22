ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

LABEL dind.project="true"

WORKDIR /coverage_reloaded

# docker.io for DinD; libpq-dev / unixodbc-dev for the pg-native and ibm_db
# native builds; sudo for the db2 start scripts (2021-12 -> 2023-07), which call
# `sudo docker ...` (we run as root, so sudo just re-execs).
RUN apt-get update && apt-get install -y \
      docker.io \
      libpq-dev \
      unixodbc-dev \
      sudo \
      --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Docker Compose v2 CLI plugin, pinned. The repo's dev/*/start.sh scripts use
# both `docker-compose` (v1 era) and `docker compose` (v2 era); the plugin plus
# the shim below let both forms run unchanged.
RUN mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fsSL \
      https://github.com/docker/compose/releases/download/v5.0.2/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose \
    && printf '#!/bin/sh\nexec docker compose "$@"\n' > /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose

# ibm_db's era clidriver for ibm_db >= 3.3.0 (v12.1.0) needs GLIBC 2.32-2.34;
# bullseye ships 2.31. glibc is backward-compatible, so pull only the libc from
# bookworm and leave the rest of the image on bullseye.
RUN echo 'deb http://deb.debian.org/debian bookworm main' > /etc/apt/sources.list.d/bookworm.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends -t bookworm \
         libc6 libc6-dev libc-bin libstdc++6 libgcc-s1 \
    && rm -rf /var/lib/apt/lists/* \
    && ldd --version | head -1

# Pre-stage the DB2 clidriver, one version per ibm_db era. ibm_db appends its
# clidriver version to the *URL*, then IBM_DB_INSTALLER_URL overrides that URL
# wholesale — so the version suffix is discarded and the installer always
# fetches <IBM_DB_INSTALLER_URL>/linuxx64_odbc_cli.tar.gz. Hence one directory
# per era, each with the tarball at its top level. install-and-run.sh picks the
# dir matching the commit's era:
#   ibm_db <  3.3.0 -> /opt/ibm-clidriver/v11  (v11.5.4, un-prefixed messages)
#   ibm_db >= 3.3.0 -> /opt/ibm-clidriver/v12  (v12.1.0, "An error or warning occurred." prefix)
RUN mkdir -p /opt/ibm-clidriver/v11 /opt/ibm-clidriver/v12 \
    && curl -fsSL \
      https://github.com/ibmdb/db2drivers/raw/main/clidriver/v11.5.4/linuxx64_odbc_cli.tar.gz \
      -o /opt/ibm-clidriver/v11/linuxx64_odbc_cli.tar.gz \
    && curl -fsSL \
      https://github.com/ibmdb/db2drivers/raw/main/clidriver/v12.1.0/linuxx64_odbc_cli.tar.gz \
      -o /opt/ibm-clidriver/v12/linuxx64_odbc_cli.tar.gz

# js-yaml (YAML 1.2) for the mysql/mariadb compose patch that disables InnoDB
# native AIO (disable-innodb-native-aio.js). Installed in its own directory so
# Node resolves it from the script and it never leaks into the repo's node_modules.
RUN mkdir -p /opt/aio-patch \
    && printf '{"private":true}\n' > /opt/aio-patch/package.json \
    && cd /opt/aio-patch \
    && npm install --no-fund --no-audit js-yaml@4.1.0 \
    && rm -rf /root/.npm

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
COPY ./disable-innodb-native-aio.js /opt/aio-patch/disable-innodb-native-aio.js
RUN chmod +x /coverage_reloaded/install-and-run.sh
