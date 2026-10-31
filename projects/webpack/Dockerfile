ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

ENV GITHUB_ACTIONS=true

WORKDIR /coverage_reloaded

COPY ./repo /coverage_reloaded/repo_disk
COPY ./mock-code-of-conduct.js /coverage_reloaded/mock-code-of-conduct.js
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
