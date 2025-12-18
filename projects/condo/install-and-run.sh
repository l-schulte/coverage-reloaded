#!/bin/bash
cd /app/repo

# yarn.lock files often contain resolved URLs to central repositories.
# Workaround 1: remove those lines to let yarn resolve them via the configured registry (waypack & verdaccio).
# [ -f "yarn.lock" ] && sed -i '/^  resolved/d' yarn.lock
# Workaround 2: replace URLs with waypack URL (https://registry.yarnpkg.com/)
[ -f "yarn.lock" ] && sed -i 's#resolved "https://registry.yarnpkg.com/#resolved "http://waypack:3000/yarn/'"$timestamp"'/#g' yarn.lock


yarn install --silent

set +e
# Yarn workspaces does not work with nyc directly. Ends up overwriting the coverage 
# report from each workspace instead of combining them. Generating them into different 
# report-dirs does not work.
# Workaround: rely on each workspace generating its own lcov.info file, which works for
#   condo since coverage seems to be collected in the individual packages anyway. Then
#   we find and move them afterwards.
    
if yarn workspaces foreach --help >/dev/null 2>&1; then
    echo "Using yarn workspaces foreach to run tests with coverage..."
    yarn workspaces foreach run test --coverage
else
    echo "Using yarn workspaces run to run tests with coverage..."
    # Older versions of yarn do not have 'workspaces foreach'.
    # Workaround: use 'workspaces run' instead.
    yarn workspaces run test --coverage
fi
bash ../find-and-move-lcov.sh
set -e