ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base
LABEL dind.project="true"

WORKDIR /coverage_reloaded

RUN apt-get update && apt-get install -y docker.io jq default-jre-headless && rm -rf /var/lib/apt/lists/*

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
