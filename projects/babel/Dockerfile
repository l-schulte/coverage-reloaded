ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
COPY ./yarn-workers-shim /coverage_reloaded/yarn-workers-shim
COPY ./browserslist-child-env.cjs /coverage_reloaded/browserslist-child-env.cjs
RUN chmod +x /coverage_reloaded/install-and-run.sh /coverage_reloaded/yarn-workers-shim
