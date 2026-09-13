ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
COPY ./silence-console.cjs /coverage_reloaded/silence-console.cjs
RUN chmod +x /coverage_reloaded/install-and-run.sh
