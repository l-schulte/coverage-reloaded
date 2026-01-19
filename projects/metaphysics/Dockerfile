FROM debian:bullseye-slim

ARG REPO=https://github.com/artsy/metaphysics
ARG NODE_VERSION=22

WORKDIR /app

RUN apt-get update && apt-get install -y git
RUN git clone ${REPO} repo

RUN apt-get install -y curl bash make build-essential zip

ENV N_PREFIX=/root/n
ENV PATH="$N_PREFIX/bin:${PATH}"

RUN curl -L https://bit.ly/n-install | bash -s -- -y
RUN n "$NODE_VERSION"
RUN node --version
RUN npm install -g yarn

COPY ./execute.sh /app/execute.sh
COPY ./install-and-run.sh /app/install-and-run.sh
RUN chmod +x /app/install-and-run.sh /app/execute.sh