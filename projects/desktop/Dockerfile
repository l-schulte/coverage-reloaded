ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
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
        git-lfs \
        && rm -rf /var/lib/apt/lists/*

# dugite downloads a prebuilt `dugite-native-*-ubuntu` git (2.39.3 in the
# 2022-05 -> 2023-12 window) that needs GLIBC 2.32-2.34; bullseye ships 2.31, so
# every git-backed unit test dies with "GLIBC_2.32 not found". glibc is
# backward-compatible, so pull only the libc from bookworm and leave the rest of
# the image on bullseye. Same fix as projects/sequelize/Dockerfile.
RUN echo 'deb http://deb.debian.org/debian bookworm main' > /etc/apt/sources.list.d/bookworm.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends -t bookworm \
         libc6 libc6-dev libc-bin libstdc++6 libgcc-s1 \
    && rm -rf /var/lib/apt/lists/* \
    && ldd --version | head -1

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
