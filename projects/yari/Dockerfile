ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

# gifsicle and other native modules need autotools to compile from source
# Puppeteer tests need system Chromium (only for test:testing - e2e test)
# RUN apt-get update && apt-get install -y \
#     autoconf \
#     automake \
#     libtool \
#     chromium \
#     --no-install-recommends \
#     && rm -rf /var/lib/apt/lists/*

# ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
# ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
# ENV CHROME_BIN=/usr/bin/chromium

# Clone content repo early so it stays cached as long as the base image is the same
RUN git clone https://github.com/mdn/content /coverage_reloaded/content

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh