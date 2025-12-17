ARG BASE_IMAGE=node:22-bullseye
FROM ${BASE_IMAGE}

WORKDIR /app

RUN cat /etc/debian_version && \
    if grep -q "^10" /etc/debian_version; then \
      sed -i 's/deb.debian.org/archive.debian.org/g' /etc/apt/sources.list && \
      sed -i 's/security.debian.org/archive.debian.org/g' /etc/apt/sources.list; \
    fi

RUN apt-get update && apt-get install -y git zip bash chromium

ARG REPO=https://github.com/getsentry/sentry-javascript

RUN git clone ${REPO} repo

COPY ./run-coverage.sh /app/run-coverage.sh
RUN chmod +x /app/run-coverage.sh