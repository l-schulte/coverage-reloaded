ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
COPY ./buildRequests.noop.js /coverage_reloaded/buildRequests.noop.js
RUN chmod +x /coverage_reloaded/install-and-run.sh