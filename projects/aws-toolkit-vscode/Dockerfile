ARG NODE_VERSION=22
FROM core_node${NODE_VERSION}_base

WORKDIR /app

RUN apt-get update && apt-get install -y chromium

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
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
RUN if ! command -v python >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then \
        ln -sf /usr/bin/python3 /usr/bin/python; \
    fi

# GitHub is deprecating the git:// protocol.
# Workaround: configure git to use https:// instead of git:// for github.com.
RUN git config --global url."https://github.com/".insteadOf "git://github.com/"s

# While there is a --headless flag for the tests, it causes segmentation faults for some commits.
# Workaround: install a lightweight desktop environment and run the tests in a virtual framebuffer.
COPY ./desktop-lite-debian.sh /tmp/desktop-lite-debian.sh
COPY ./desktop-init.sh /tmp/desktop-init.sh
RUN chmod +x /tmp/desktop-lite-debian.sh /tmp/desktop-init.sh
RUN /tmp/desktop-lite-debian.sh

COPY ./repo /app/repo

COPY ./install-and-run.sh /app/install-and-run.sh
COPY ./restore_vscode.py /app/restore_vscode.py
COPY ./store_vscode.py /app/store_vscode.py
RUN chmod +x /app/install-and-run.sh