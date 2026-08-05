ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

RUN apt-get update && apt-get install -y \
  chromium \
  default-mysql-server \
  redis-server \
  --no-install-recommends \
  && rm -rf /var/lib/apt/lists/*

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV CHROME_BIN=/usr/bin/chromium

COPY ./harness /coverage_reloaded/harness
RUN chmod +x /coverage_reloaded/harness/validate.sh

RUN cd /coverage_reloaded/harness && npm install \
  istanbul-lib-instrument \
  istanbul-lib-coverage \
  istanbul-lib-report \
  istanbul-reports \
  istanbul-lib-source-maps \
  remap-istanbul \
  source-map \
  karma-coverage \
  "@babel/core@7.22.0" \
  "@babel/preset-env@7.22.0" \
  karma-babel-preprocessor \
  gulp-sourcemaps

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh