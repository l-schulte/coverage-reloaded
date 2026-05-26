ARG NODE_VERSION=24
FROM core_node${NODE_VERSION}_base

WORKDIR /coverage_reloaded

# Vuetify uses vitest which can run both unit (jsdom) and browser (Playwright)
# tests. Install Playwright Chromium for browser test support if needed.
RUN npx playwright install --with-deps chromium 2>/dev/null || true

# Cypress component tests (mid-era commits) need a virtual display
# and various system libraries (GLib, GTK, Atk, etc.).
# xvfb provides the virtual display — no desktop environment or VNC required.
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

COPY ./repo /coverage_reloaded/repo
COPY ./install-and-run.sh /coverage_reloaded/install-and-run.sh
COPY ./cypress-coverage-setup.sh /coverage_reloaded/cypress-coverage-setup.sh
COPY ./vite-istanbul-wrapper.mjs /coverage_reloaded/vite-istanbul-wrapper.mjs
RUN chmod +x /coverage_reloaded/install-and-run.sh /coverage_reloaded/cypress-coverage-setup.sh
