ARG BASE_IMAGE=node:22-bullseye
FROM ${BASE_IMAGE}

WORKDIR /app

RUN cat /etc/debian_version && \
    if grep -q "^10" /etc/debian_version; then \
      sed -i 's/deb.debian.org/archive.debian.org/g' /etc/apt/sources.list && \
      sed -i 's/security.debian.org/archive.debian.org/g' /etc/apt/sources.list; \
    fi

RUN apt-get update && apt-get install -y git

ARG REPO=https://github.com/tinacms/tinacms

RUN git clone ${REPO} repo

RUN apt-get update && apt-get install -y zip bash chromium

COPY ./execute.sh /app/execute.sh
COPY ./install-and-run.sh /app/install-and-run.sh
RUN chmod +x /app/install-and-run.sh /app/execute.sh