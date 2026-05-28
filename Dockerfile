# Base Dockerfile for a Node.js application

FROM debian:bullseye-slim
ARG NODE_VERSION=22

WORKDIR /coverage_reloaded

RUN apt-get update && \
    apt-get install -y \
        git \
        curl \
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
RUN curl -Ls https://astral.sh/uv/install.sh | sh
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

RUN apt-get install -y libfaketime

COPY ./execute.sh /coverage_reloaded/execute.sh
RUN chmod +x /coverage_reloaded/execute.sh

COPY helper/find-and-move-lcov.sh /coverage_reloaded/find-and-move-lcov.sh
COPY helper/logging.sh /coverage_reloaded/logging.sh
COPY helper/fake-time.sh /coverage_reloaded/fake-time.sh
RUN chmod +x /coverage_reloaded/find-and-move-lcov.sh /coverage_reloaded/logging.sh /coverage_reloaded/fake-time.sh

COPY helper/cypress/cypress-patcher.sh /coverage_reloaded/cypress-patcher.sh
RUN chmod +x /coverage_reloaded/cypress-patcher.sh

