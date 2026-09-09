ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

RUN apt-get update && apt-get install -y \
  chromium \
  redis-server \
  wget \
  # default-mysql-server \   # previously used; Debian bullseye provides MariaDB 10.5, but bhima targets MySQL 8.0
  --no-install-recommends \
  && rm -rf /var/lib/apt/lists/*

# MySQL 8.0 from the official MySQL APT repository, configured directly.
# We avoid the mysql-apt-config .deb: its gnupg/lsb-release pre-dependencies
# conflict with the pinned bullseye archive (gnupg wants an older gpgv than the
# one available). [trusted=yes] + --allow-unauthenticated let apt install the
# server without GPG tooling. This matches bhima's CI target
# (sh/travis-install-mysql8.sh): MySQL 8.0. MariaDB 10.5's stored-procedure /
# NOT-NULL / charset behaviour diverges from MySQL 8 and breaks bhima's build:db
# seed (count mismatches, ER_BAD_NULL, latin1 mojibake).
RUN echo 'deb [trusted=yes] http://repo.mysql.com/apt/debian bullseye mysql-8.0' > /etc/apt/sources.list.d/mysql.list \
  && apt-get update -q \
  && DEBIAN_FRONTEND=noninteractive apt-get install -q -y --allow-unauthenticated mysql-server \
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