ARG NODE_VERSION=16
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

# This project's package.json carries a legacy `devEngines` block
# ({"node": ">=7.9.x", "npm": ">=3.x"}) that npm >= 10.9 hard-rejects with
# "Invalid property devEngines.node" whenever npm reads it.  execute.sh runs
# `npm config set` with cwd at the repo root, before install-and-run.sh, so the
# run aborts there for the node-22 commits.  location=global stops npm from
# loading the project package.json.  install-and-run.sh unsets this so the
# install/test phases run with npm's normal behaviour.
# Project-specific workaround: do not copy to other projects without a
# concrete reason (see commit history for the npm 10.9 devEngines validation).
ENV NPM_CONFIG_LOCATION=global

RUN apt-get update && \
    LIBUDEV1_VERSION=$(apt-cache show libudev-dev | sed -n 's/^Depends:.*libudev1 (= \([^)]*\)).*/\1/p' | head -1) && \
    apt-get install -y --no-install-recommends --allow-downgrades \
        "libudev1=${LIBUDEV1_VERSION}" \
        xvfb \
        xauth \
        libnss3 \
        libnspr4 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libcups2 \
        libdrm2 \
        libgbm1 \
        libglib2.0-0 \
        libgtk-3-0 \
        libgdk-pixbuf2.0-0 \
        libpango-1.0-0 \
        libcairo2 \
        libasound2 \
        libxss1 \
        libx11-xcb1 \
        libxcb-dri3-0 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxfixes3 \
        libxi6 \
        libxrandr2 \
        libxshmfence1 \
        libxtst6 \
        libxkbcommon0 \
        libsecret-1-0 \
        libsecret-1-dev \
        libudev-dev \
        libusb-1.0-0 \
        libusb-1.0-0-dev \
        libavutil-dev \
        libcanberra-gtk3-module \
        packagekit-gtk3-module \
        fonts-liberation \
        && rm -rf /var/lib/apt/lists/*

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
