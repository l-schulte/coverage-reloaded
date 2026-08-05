ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

# Install Ruby 2.7 + Java 11 for invokeLocal tests
# Ruby 2.7: default in Bullseye, covers ruby2.5/ruby2.7/ruby3.2 tests (100% of 2020-2025 scope)
# Java 11: covers java8/java11/java17/java21 tests (backward compatible, 100% coverage)
RUN apt-get update && apt-get install -y \
    ruby-full \
    openjdk-11-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /coverage_reloaded

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh