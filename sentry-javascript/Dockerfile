FROM node:22-alpine

WORKDIR /app

RUN apk add git

ARG REPO=https://github.com/getsentry/sentry-javascript

RUN git clone ${REPO} repo

RUN apk add zip bash

COPY ./run-coverage.sh /app/run-coverage.sh
COPY ./tmp/go-waypack.sh /app/go-waypack.sh
RUN chmod +x /app/run-coverage.sh /app/go-waypack.sh