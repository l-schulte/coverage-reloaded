ARG NODE_VERSION=24
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

# Install system dependencies for Cypress component tests (mid-era commits):
# xvfb for virtual display, GTK/GLib/Cairo/etc. for the Cypress Electron app.
# These are needed by Cypress regardless of which commit is tested.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        xvfb \
        libglib2.0-0 \
        libgtk-3-0 \
        libgdk-pixbuf2.0-0 \
        libpango-1.0-0 \
        libcairo2 \
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
        libnss3 \
        && rm -rf /var/lib/apt/lists/*

COPY cypress-coverage-configs /coverage_reloaded/cypress-coverage-configs

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
