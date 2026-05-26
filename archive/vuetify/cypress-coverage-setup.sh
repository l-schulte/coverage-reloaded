#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# cypress-coverage-setup.sh
# Detects Cypress era, instruments the project, runs Cypress with coverage,
# and moves LCOV output.
#
# Sources: /coverage_reloaded/logging.sh
#
# Exit codes:
#   0  — Cypress ran (success or test failures — coverage collected)
#   1  — skipped (no config / no cy:run) or not implemented (v8 placeholder)
#   >1 — Cypress runner crashed and exit code is propagated
# ──────────────────────────────────────────────────────────────────────────────

source /coverage_reloaded/logging.sh

# ── Working directory ─────────────────────────────────────────────────────────
# Always packages/vuetify inside the repo
cd /coverage_reloaded/repo/packages/vuetify

# ═══════════════════════════════════════════════════════════════════════════════
# 1. DETECT CYPRESS ERA
# ═══════════════════════════════════════════════════════════════════════════════

print_header 1 "Cypress Coverage Setup" "Detecting Cypress era"

CYPRESS_ERA=""
if [ -f cypress.config.ts ]; then
    CYPRESS_ERA="v10"
elif [ -f cypress.config.js ]; then
    CYPRESS_ERA="v10"
elif [ -f cypress.config.mjs ]; then
    CYPRESS_ERA="v10"
elif [ -f cypress.json ]; then
    CYPRESS_ERA="v8"
fi

if [ -z "$CYPRESS_ERA" ]; then
    print_header 3 "No Cypress config found — skipping"
    exit 1
fi

print_header 3 "Detected Cypress era" "$CYPRESS_ERA"

# ═══════════════════════════════════════════════════════════════════════════════
# 2. READ cy:run FROM PACKAGE.JSON
# ═══════════════════════════════════════════════════════════════════════════════

print_header 2 "Reading cy:run from package.json"

CYPRESS_CMD="$(node -p "const p = require('./package.json'); (p.scripts && p.scripts['cy:run']) || ''")"

if [ -z "$CYPRESS_CMD" ]; then
    print_header 3 "cy:run not found in package.json scripts — skipping"
    exit 1
fi

print_header 3 "Original cy:run command" "$CYPRESS_CMD"

# ── Strip percy exec -- prefix ────────────────────────────────────────────────
# Some commits wrap the command with "percy exec -- " for visual diff screenshots.
# Since percy is not installed, strip it.
CYPRESS_CMD="${CYPRESS_CMD#percy exec -- }"
print_header 3 "After stripping percy prefix" "$CYPRESS_CMD"

# ── Strip --bail and --headed ─────────────────────────────────────────────────
# --bail stops tests at first failure, silently producing incomplete coverage.
# --headed opens a visible browser window (not needed in CI).
CYPRESS_CMD="${CYPRESS_CMD/--bail/}"
CYPRESS_CMD="${CYPRESS_CMD/--headed/}"
# Collapse multiple spaces left behind after stripping
CYPRESS_CMD="$(echo "$CYPRESS_CMD" | tr -s ' ')"
print_header 3 "After stripping --bail and --headed" "$CYPRESS_CMD"

# ═══════════════════════════════════════════════════════════════════════════════
# 3. START XVFB IF NEEDED
# ═══════════════════════════════════════════════════════════════════════════════

print_header 2 "Display / Xvfb setup"

if [ -z "${DISPLAY:-}" ]; then
    print_header 3 "DISPLAY not set — starting Xvfb on :99"
    export DISPLAY=:99
    Xvfb :99 -screen 0 1920x1080x24 &
    XVFB_PID="$!"
    sleep 1  # Give it a moment to start
else
    print_header 3 "DISPLAY already set to $DISPLAY"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 4. BRANCH BY ERA
# ═══════════════════════════════════════════════════════════════════════════════

if [ "$CYPRESS_ERA" = "v10" ]; then

    # ──────────────────────────────────────────────────────────────────────────
    # v10 — Full implementation
    # ──────────────────────────────────────────────────────────────────────────

    print_header 1 "Cypress v10 — instrumenting for coverage"

    # ── 4a. Install @cypress/code-coverage and vite-plugin-istanbul ──────────
    print_header 2 "Installing coverage plugins"
    print_header 3 "Installing @cypress/code-coverage and vite-plugin-istanbul"
    npm install --no-save --no-fund --legacy-peer-deps \
        @cypress/code-coverage \
        vite-plugin-istanbul

    # ── 4b. Deploy vite-plugin-istanbul wrapper ─────────────────────────────
    print_header 2 "Deploying vite-plugin-istanbul wrapper"
    if grep -q "vite-plugin-istanbul" vite.config.mjs 2>/dev/null; then
        print_header 3 "vite-plugin-istanbul already present — skipping"
    else
        mv vite.config.mjs _vite.config.mjs
        cp /coverage_reloaded/vite-istanbul-wrapper.mjs vite.config.mjs
        print_header 3 "Deployed vite wrapper (original → _vite.config.mjs)"
    fi

    # ── 4c. Patch cypress.config.ts ─────────────────────────────────────────
    print_header 2 "Patching cypress.config.ts"

    if grep -q "coverageTask\|@cypress/code-coverage/task" cypress.config.ts 2>/dev/null; then
        print_header 3 "cypress.config.ts already patched — skipping"
    else
        print_header 3 "Adding coverageTask import and setupNodeEvents"

        # Add import after first line
        TMPFILE="$(mktemp)"
        awk '
        NR == 1 { print; print "import coverageTask from '\''@cypress/code-coverage/task'\'';"; next }
        { print }
        ' cypress.config.ts > "$TMPFILE" && mv "$TMPFILE" cypress.config.ts

        # Inject setupNodeEvents inside component: block right after devServer: { },
        # only if not already present
        if ! grep -q "setupNodeEvents" cypress.config.ts; then
            TMPFILE="$(mktemp)"
            awk '
            /devServer:/ { found_devserver = 1 }
            found_devserver && !done && /^    \},/ {
                print
                print "    setupNodeEvents (on, config) {"
                print "      coverageTask(on, config)"
                print "      return config"
                print "    },"
                done = 1
                next
            }
            { print }
            ' cypress.config.ts > "$TMPFILE" && mv "$TMPFILE" cypress.config.ts
        fi

        print_header 3 "cypress.config.ts patched"
    fi

    # ── 4d. Patch cypress/support/index.ts ──────────────────────────────────
    print_header 2 "Patching cypress/support/index.ts"

    SUPPORT_FILE="cypress/support/index.ts"
    if [ ! -f "$SUPPORT_FILE" ]; then
        SUPPORT_FILE="cypress/support/index.js"
    fi
    if [ ! -f "$SUPPORT_FILE" ]; then
        SUPPORT_FILE=""
    fi

    if [ -z "$SUPPORT_FILE" ]; then
        print_header 3 "WARNING: No support file found at cypress/support/index.ts or .js"
    elif grep -q "@cypress/code-coverage/support" "$SUPPORT_FILE" 2>/dev/null; then
        print_header 3 "cypress/support already patched — skipping"
    else
        print_header 3 "Commenting out @percy/cypress import and adding @cypress/code-coverage/support"

        # Comment out any @percy/cypress import
        sed -i "s|import '@percy/cypress'|// import '@percy/cypress'|g" "$SUPPORT_FILE"
        sed -i "s|require('@percy/cypress')|// require('@percy/cypress')|g" "$SUPPORT_FILE"

        # Append coverage support import
        echo "import '@cypress/code-coverage/support';" >> "$SUPPORT_FILE"

        print_header 3 "Patched $SUPPORT_FILE"
    fi

    # ── 4e. Run Cypress ─────────────────────────────────────────────────────
    print_header 1 "Running Cypress" "Command: npx $CYPRESS_CMD"

    set +e
    npx $CYPRESS_CMD
    CYPRESS_EXIT_CODE="$?"
    set -e

    print_header 3 "Cypress exit code" "$CYPRESS_EXIT_CODE"

    # ── 4f. Collect coverage ────────────────────────────────────────────────
    print_header 2 "Collecting coverage reports"
    cd /coverage_reloaded/repo
    bash /coverage_reloaded/find-and-move-lcov.sh "cypress" "true"

    # ── 4h. Exit with Cypress exit code ─────────────────────────────────────
    exit "$CYPRESS_EXIT_CODE"

elif [ "$CYPRESS_ERA" = "v8" ]; then

    # ──────────────────────────────────────────────────────────────────────────
    # v8 — Placeholder: not yet implemented
    # ──────────────────────────────────────────────────────────────────────────

    print_header 1 "Cypress v8 era — not implemented"

    cat <<'EOF'

  ╔══════════════════════════════════════════════════════════════════╗
  ║  ERROR: Cypress v8 era (cypress.json-based) is not yet          ║
  ║  implemented.                                                   ║
  ║                                                                  ║
  ║  Only Cypress v10 (cypress.config.ts/.js/.mjs-based) is         ║
  ║  supported at this time.                                        ║
  ╚══════════════════════════════════════════════════════════════════╝

EOF

    exit 1

fi
