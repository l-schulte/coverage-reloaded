ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base
LABEL dind.project="true"

WORKDIR /coverage_reloaded

# Install Docker daemon for Docker-in-Docker.
# MongoDB and possibly other external services are started via Docker
# inside the container during test execution.
RUN apt-get update && apt-get install -y docker.io wget

# Pre-download FoundationDB DEB packages for both FDB 6.3.x and FDB 7.3.x.
# The project switched from FDB 6.3.x (apiVersion 630) to FDB 7.3.x
# (apiVersion 720) at commit 66babde21. The runtime script installs the
# correct version per commit. Neither is installed at build time.
#
# FDB 6.3.23 DEBs — for commits before 66babde21
# FDB 7.3.77 DEBs — for commits after  66babde21
RUN wget -O /opt/fdb6-clients.deb https://github.com/apple/foundationdb/releases/download/6.3.23/foundationdb-clients_6.3.23-1_amd64.deb && \
    wget -O /opt/fdb6-server.deb https://github.com/apple/foundationdb/releases/download/6.3.23/foundationdb-server_6.3.23-1_amd64.deb && \
    wget -O /opt/fdb7-clients.deb https://github.com/apple/foundationdb/releases/download/7.3.77/foundationdb-clients_7.3.77-1_amd64.deb && \
    wget -O /opt/fdb7-server.deb https://github.com/apple/foundationdb/releases/download/7.3.77/foundationdb-server_7.3.77-1_amd64.deb

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh