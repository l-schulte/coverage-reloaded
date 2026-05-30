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

# Install Google Chrome for Vitest browser tests (webdriverio provider).
# The vitest.workspace.ts defines a 'browser' project that runs
# *.spec.browser.* files in Chrome via webdriverio. Without Chrome
# installed, vitest throws:
#   TypeError: __vitest_browser_runner__.runTests is not a function
# See: https://github.com/vitest-dev/vitest/issues/6674
RUN curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends google-chrome-stable && \
    rm -rf /var/lib/apt/lists/*

COPY cypress-coverage-configs /coverage_reloaded/cypress-coverage-configs

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
RUN chmod +x /coverage_reloaded/install-and-run.sh
