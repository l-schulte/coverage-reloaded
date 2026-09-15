ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base
LABEL dind.project="true"

WORKDIR /coverage_reloaded

# Docker-in-Docker: both packages/search and packages/events use testcontainers
# to spin up real Elasticsearch 8.16.4 containers during tests.
RUN apt-get update && apt-get install -y docker.io && rm -rf /var/lib/apt/lists/*

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
COPY ./patch-coverage.js /coverage_reloaded/patch-coverage.js
RUN chmod +x /coverage_reloaded/install-and-run.sh
