ARG NODE_VERSION=12
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh