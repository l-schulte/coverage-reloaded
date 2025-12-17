ARG BASE_IMAGE=node:22-bullseye
FROM ${BASE_IMAGE}

WORKDIR /app

RUN cat /etc/debian_version && \
    if grep -q "^10" /etc/debian_version; then \
      sed -i 's/deb.debian.org/archive.debian.org/g' /etc/apt/sources.list && \
      sed -i 's/security.debian.org/archive.debian.org/g' /etc/apt/sources.list; \
    fi

RUN apt-get update && apt-get install -y git zip bash chromium

ARG REPO=https://github.com/aws/aws-toolkit-vscode

RUN git clone ${REPO} repo

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget \
        gpg \
        libsecret-1-dev \
        libxkbfile-dev \
        libkrb5-dev \
        libgtk-3-0 \
        libnss3 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libasound2 \
        libxss1 \
        libx11-xcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxi6 \
        libxtst6 \
        libgbm1 \
        jq

RUN apt-get update && \
    apt-get install -y xvfb xauth xfonts-100dpi xfonts-75dpi xfonts-scalable xfonts-cyrillic

RUN rm -rf /var/lib/apt/lists/*

# Set the DISPLAY environment variable
ENV DISPLAY=:99

# Gulp sometimes requires python, and does not always specify python3.
# Workaround: create a symlink from python3 to python.
RUN ln -s /usr/bin/python3 /usr/bin/python

# GitHub is deprecating the git:// protocol.
# Workaround: configure git to use https:// instead of git:// for github.com.
RUN git config --global url."https://github.com/".insteadOf "git://github.com/"

# While there is a --headless flag for the tests, it causes segmentation faults for some commits.
# Workaround: install a lightweight desktop environment and run the tests in a virtual framebuffer.
COPY ./desktop-lite-debian.sh /tmp/desktop-lite-debian.sh
COPY ./desktop-init.sh /tmp/desktop-init.sh
RUN chmod +x /tmp/desktop-lite-debian.sh /tmp/desktop-init.sh
RUN /tmp/desktop-lite-debian.sh

# Running Main test suite...
# Setting up VS Code test instance, version: stable
# Found existing install in /app/repo/.vscode-test/vscode-linux-x64-1.107.0. Skipping download
# VS Code test instance location: /app/repo/.vscode-test/vscode-linux-x64-1.107.0/code
# Invoking vscode CLI command:
#     "/app/repo/.vscode-test/vscode-linux-x64-1.107.0/bin/code" ["--extensions-dir=/app/repo/.vscode-test/extensions","--user-data-dir=/app/repo/.vscode-test/user-data","--version"]
# 1.107.0
# 618725e67565b290ba4da6fe2d29f8fa1d4e3622
# x64

RUN mkdir -p /repo/.vscode-test
RUN wget https://update.code.visualstudio.com/1.107.0/linux-x64/stable -O vscode-linux-x64-1.107.0.tar.gz

COPY ./execute.sh /app/execute.sh
COPY ./install-and-run.sh /app/install-and-run.sh
RUN chmod +x /app/install-and-run.sh /app/execute.sh