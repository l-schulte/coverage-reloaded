ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

# GNU parallel is needed for the run-tests.sh script (era 3)
RUN apt-get update && apt-get install -y --no-install-recommends parallel && rm -rf /var/lib/apt/lists/*

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
