ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

# Prebuilt tree-sitter (via curlconverter in editor-ui) requires GLIBCXX_3.4.29;
# bullseye base ships GLIBCXX_3.4.28. Pull libc and libstdc++ from bookworm
# while keeping the rest of the image on bullseye. Same pattern as
# projects/opencrvs-core, projects/desktop and projects/sequelize.
RUN echo 'deb http://deb.debian.org/debian bookworm main' > /etc/apt/sources.list.d/bookworm.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends -t bookworm \
         libc6 libc6-dev libc-bin libstdc++6 libgcc-s1 \
    && rm -rf /var/lib/apt/lists/* \
    && ldd --version | head -1

WORKDIR /coverage_reloaded

COPY ./repo /coverage_reloaded/repo_disk
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
COPY ./patch-coverage.js /coverage_reloaded/patch-coverage.js
RUN chmod +x /coverage_reloaded/install-and-run.sh
