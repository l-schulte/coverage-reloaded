# Base Dockerfile for a Node.js application

FROM debian:bullseye-slim
ARG NODE_VERSION=22

WORKDIR /coverage_reloaded

# Bullseye is oldstable: its debian-security pool has been drained, so the
# +deb11uN packages now live in the main suite. Source from there and retry
# on flaky mirrors. (python2.7 at line 22 still resolves from bullseye main.)
RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/* && \
    printf '%s\n' \
      'deb http://deb.debian.org/debian bullseye main' \
      > /etc/apt/sources.list && \
    echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/99retries && \
    apt-get update && \
    apt-get install -y --no-install-recommends --allow-downgrades \
        libc6=2.31-13+deb11u11 libc6-dev=2.31-13+deb11u11 \
        perl-base=5.32.1-4+deb11u3 perl=5.32.1-4+deb11u3 \
        git \
        curl \
        ca-certificates \
        wget \
        bash \
        make \
        build-essential \
        cmake \
        zip \
        nano \
        lcov=1.14-2 \
        jq

RUN apt-get update && apt-get install -y python2.7 && \
    update-alternatives --install /usr/bin/python2 python2 /usr/bin/python2.7 1

# RUN ln -s /usr/bin/python2 /usr/local/bin/python

# uv for Python 3
RUN curl -L https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"
RUN uv python install 3.10 3.8

RUN NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1) && \
    if [ "$NODE_MAJOR" -le 12 ]; then \
        PYTHON_BIN=$(uv python find 3.8); \
    else \
        PYTHON_BIN=$(uv python find 3.10); \
    fi && \
    ln -sf "$PYTHON_BIN" /usr/local/bin/python && \
    ln -sf "$PYTHON_BIN" /usr/local/bin/python3 && \
    ln -sf "$PYTHON_BIN" /usr/bin/python && \
    ln -sf "$PYTHON_BIN" /usr/bin/python3

RUN python --version && echo "Python set for Node ${NODE_VERSION}"

RUN curl -L https://bit.ly/n-install | bash -s -- -y

ENV N_PREFIX=/root/n
ENV PATH="$N_PREFIX/bin:${PATH}"

RUN n "$NODE_VERSION"
RUN node --version

# Problem: test runner starts in watch mode, expecting user input
# Solution: set CI=true to disable watch mode and run tests once
ENV CI=true

# We install dependencies at historical timestamps, so caniuse-lite data
# will always be "old" relative to the container clock. Suppress the
# browserslist warning that leaks into stderr and causes false test failures.
ENV BROWSERSLIST_IGNORE_OLD_DATA=1

RUN apt-get install -y libfaketime

COPY ./execute.sh /coverage_reloaded/execute.sh
RUN chmod +x /coverage_reloaded/execute.sh

COPY helper/find-and-move-lcov.sh /coverage_reloaded/find-and-move-lcov.sh
COPY helper/logging.sh /coverage_reloaded/logging.sh
COPY helper/fake-time.sh /coverage_reloaded/fake-time.sh
COPY helper/has-option.sh /coverage_reloaded/has-option.sh
COPY helper/resolve-and-pin.sh /coverage_reloaded/resolve-and-pin.sh
RUN chmod +x /coverage_reloaded/find-and-move-lcov.sh /coverage_reloaded/logging.sh /coverage_reloaded/fake-time.sh /coverage_reloaded/has-option.sh /coverage_reloaded/resolve-and-pin.sh

COPY helper/fake-time-node.js /coverage_reloaded/fake-time-node.js
RUN chmod +x /coverage_reloaded/fake-time-node.js

COPY helper/cypress/cypress-patcher.sh /coverage_reloaded/cypress-patcher.sh
RUN chmod +x /coverage_reloaded/cypress-patcher.sh

