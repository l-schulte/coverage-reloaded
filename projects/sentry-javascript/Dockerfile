ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /app

COPY ./repo /app/repo
COPY ./install-and-run.sh /app/install-and-run.sh
RUN chmod +x /app/install-and-run.sh