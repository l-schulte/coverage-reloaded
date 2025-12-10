ARG BASE_IMAGE=node:22-alpine
FROM ${BASE_IMAGE}

WORKDIR /app

RUN apk add --no-cache git

ARG REPO=https://github.com/ChainSafe/lodestar

RUN git clone ${REPO} repo

RUN apk add --no-cache \
    zip \
    bash \
    chromium \
    python3 \
    py3-pip \
    g++ \
    make

COPY ./run-coverage.sh /app/run-coverage.sh
COPY ./tmp/go-waypack.sh /app/go-waypack.sh
RUN chmod +x /app/run-coverage.sh /app/go-waypack.sh