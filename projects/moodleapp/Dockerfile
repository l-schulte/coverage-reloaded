ARG NODE_VERSION=12
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

# Install pkg-config and libsecret-1-dev for keytar package
RUN apt-get update && apt-get install -y pkg-config libsecret-1-dev

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
