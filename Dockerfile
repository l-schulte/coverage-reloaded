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
        cmake-latest \
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
RUN uv python install 3.11
RUN ln -sf $(uv python find 3.11) /usr/local/bin/python3
RUN ln -sf $(uv python find 3.11) /usr/bin/python3

# Default python = python3, overridden per-build for old node-gyp eras
RUN ln -sf $(uv python find 3.11) /usr/local/bin/python


RUN curl -L https://bit.ly/n-install | bash -s -- -y

ENV N_PREFIX=/root/n
ENV PATH="$N_PREFIX/bin:${PATH}"

RUN n "$NODE_VERSION"
RUN node --version
RUN npm install -g yarn
RUN yarn set version latest

# Problem: test runner starts in watch mode, expecting user input
# Solution: set CI=true to disable watch mode and run tests once
ENV CI=true

COPY ./execute.sh /coverage_reloaded/execute.sh
COPY find-and-move-lcov.sh /coverage_reloaded/find-and-move-lcov.sh
RUN chmod +x /coverage_reloaded/execute.sh /coverage_reloaded/find-and-move-lcov.sh