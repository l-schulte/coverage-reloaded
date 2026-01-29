# Base Dockerfile for a Node.js application

FROM debian:bullseye-slim
ARG NODE_VERSION=22

WORKDIR /app

RUN apt-get update && \
    apt-get install -y \
        git \
        curl \
        wget \
        bash \
        make \
        build-essential \
        zip \
        nano \
        python3 \
        lcov=1.14-2



RUN curl -L https://bit.ly/n-install | bash -s -- -y

ENV N_PREFIX=/root/n
ENV PATH="$N_PREFIX/bin:${PATH}"

RUN n "$NODE_VERSION"
RUN node --version
RUN npm install -g yarn

COPY ./execute.sh /app/execute.sh
COPY find-and-move-lcov.sh /app/find-and-move-lcov.sh
RUN chmod +x /app/execute.sh /app/find-and-move-lcov.sh