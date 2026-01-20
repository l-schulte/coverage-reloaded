#!/bin/bash

# -------------------------------------------------------------
# ATTENTION! ONLY MODIFY THE ORIGINAL
# THIS WILL BE COPIED TO EACH PROJECT'S FOLDER AUTOMATICALLY
# -------------------------------------------------------------

#!/bin/bash

starttime=$(date +%s)
cd /app/repo

process_files() {
    set +e
    local execute_function="$1"
    local processed_count=0
    local ignore_args=()

    echo "Searching for patterns: ${match_patterns[*]}"
    echo "Ignoring patterns: ${ignore_patterns[*]}"

    for ignore in "${ignore_patterns[@]}"; do
        ignore_args+=(-not -path "$ignore")
    done

    for pattern in "${match_patterns[@]}"; do
        while IFS= read -r -d '' file; do
            echo "Found file: $file"
            cmd="${execute_function/\{\}/$file}"
            eval "$cmd"
            ((processed_count++))
        done < <(find . -path "./$pattern" -type f "${ignore_args[@]}" -print0)
    done

    echo "$processed_count files processed"
    set -e
}

# GitHub is deprecating the git:// protocol.
# Workaround: configure git to use https:// instead of git:// for github.com.
git config --global url."https://github.com/".insteadOf "git://github.com/"

COVERAGE_REPORT_PATH="/app/cov_exports"
mkdir -p "$COVERAGE_REPORT_PATH"
export COVERAGE_REPORT_PATH

IS_NPM_MAIN_PM=$([[ "$package_manager" == npm* ]] && echo "true" || echo "false")
export IS_NPM_MAIN_PM

IS_YARN_MAIN_PM=$([[ "$package_manager" == yarn* ]] && echo "true" || echo "false")
export IS_YARN_MAIN_PM

IS_PNPM_MAIN_PM=$([[ "$package_manager" == pnpm* ]] && echo "true" || echo "false")
export IS_PNPM_MAIN_PM

echo "=== Starting run-coverage.sh ==="
echo "Revision: $revision"
echo "Commit date: $(date -d @$timestamp)"
echo "Timestamp: $timestamp"
echo "Package Manager: $package_manager"
echo ""
echo "=== System Information ==="
uname -a
echo ""
echo "=== Linux Distribution ==="
cat /etc/os-release
echo ""
echo "=== Git Version ==="
git --version
echo ""
echo "=== CPU Information ==="
nproc
echo ""
echo "=== Memory Information ==="
free -h
echo ""
echo "=== Disk Information ==="
df -h
echo ""
set -e
echo "=== Current Folder ==="
pwd
echo ""
echo "=== Git Checkout ==="
git checkout "$revision"
echo ""
echo "=== Node Version ==="
node --version
echo ""
echo "=== NPM Version ==="
npm --version
echo "npm main PM: $IS_NPM_MAIN_PM"
echo ""
echo "=== Yarn Version ==="
yarn --version
echo "Yarn main PM: $IS_YARN_MAIN_PM"
IS_YARN_LEGACY=$(yarn --version | grep -q "^1\." && echo "true" || echo "false")
echo "Legacy Yarn: $IS_YARN_LEGACY"
echo ""

echo "=== Setting up Package Managers ==="


# Always set npm registry to Waypack
# if [ "$IS_NPM_MAIN_PM" = "true" ] || [ "$package_manager" == "" ]; then
#     echo " --> Setup npm"
# fi
echo " --> Setup npm"
npm config set registry "http://waypack:3000/npm/$timestamp/"

# Set up yarn if it's the main package manager or no package manager is specified
if [ "$IS_YARN_MAIN_PM" = "true" ] || [ "$package_manager" == "" ]; then
    echo " --> Setup yarn"

    if [ "$IS_YARN_LEGACY" = "true" ]; then
        echo " --> Setting yarn legacy registry to Waypack..."
        yarn config set registry "http://waypack:3000/yarn/$timestamp/"
    else
        echo " --> Setting yarn modern registry to Waypack..."
        yarn config set unsafeHttpWhitelist --json '["waypack", "verdaccio"]'
        yarn config set npmRegistryServer "http://waypack:3000/yarn/$timestamp/"
    fi
fi

# Set up pnpm only if it's the main package manager
if [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    echo " --> Setup pnpm"
    # IS_PM_SPECIFIED=$(grep -q '"packageManager"' package.json && echo "true" || echo "false") # Unsure why this was needed
    # if [[ "$IS_PM_SPECIFIED" = "true" && -x "$(command -v corepack)" && "${package_manager}" == pnpm* ]]; then
    if [[ -x "$(command -v corepack)" && "${package_manager}" == pnpm* ]]; then
        echo " --> Setting up ${package_manager} via corepack..."
        corepack enable
        corepack prepare "${package_manager}" --activate
    else 
        echo " --> Installing pnpm globally via npm..."
        npm install --no-fund -g pnpm
    fi
    pnpm config set registry "http://waypack:3000/npm/$timestamp/"

    echo "=== PNPM Version ==="
    pnpm --version
    echo "pnpm main PM: $IS_PNPM_MAIN_PM"
    echo ""
fi
echo ""

echo "=== Cleaning package manager lock files ==="

# There may be a package-lock.json file with resolved URLs hardcoded to npmjs.org. Slow and potentially rate limited.
# Workaround 1: remove URLs
# Result: fails (TypeError [ERR_INVALID_ARG_TYPE]: The "paths[1]" argument must be of type string. Received undefined)
# [ -f "package-lock.json" ] && sed -i '/"resolved":/d' package-lock.json
# Workaround 2: replace URLs with waypack URL (https://registry.npmjs.org/)
# Result: works
match_patterns=('package-lock.json' '*/package-lock.json')
ignore_patterns=('*/node_modules/*')
execute_function='sed -i "s#\"resolved\": \"https://registry.npmjs.org/#\"resolved\": \"http://waypack:3000/npm/'"$timestamp"'/#g" {}'

process_files "$execute_function"

# yarn.lock files often contain resolved URLs to central repositories.
# Workaround 1: remove those lines to let yarn resolve them via the configured registry (waypack & verdaccio).
# [ -f "yarn.lock" ] && sed -i '/^  resolved/d' yarn.lock
# Workaround 2: replace URLs with waypack URL (https://registry.yarnpkg.com/)
match_patterns=('yarn.lock' '*/yarn.lock')
ignore_patterns=('*/node_modules/*')
execute_function='sed -i "s|resolved \"https://registry.yarnpkg.com/|resolved \"http://waypack:3000/yarn/'"$timestamp"'/|g" {}'

process_files "$execute_function"

echo ""

# echo "=== Setting up nyc ==="
# # Install nyc globally if not already installed
# if ! npx nyc --version >/dev/null 2>&1; then
#     echo " --> Installing nyc globally"
#     if [ "$IS_NPM_MAIN_PM" = "true" ] || [ "$package_manager" == "" ]; then
#         npm install --no-fund -g nyc
#     elif [ "$IS_YARN_MAIN_PM" = "true" ]; then
#         yarn global add nyc
#     elif [ "$IS_PNPM_MAIN_PM" = "true" ]; then
#         pnpm add -g nyc
#     fi
# else
#     echo " --> nyc is already installed"
# fi
# echo ""


echo "=== Calling install-and-run.sh ==="

timeout 5400s bash ../install-and-run.sh

echo "=== Checking coverage reports ==="
lcov_count=$(find "$COVERAGE_REPORT_PATH" -name "lcov.info" | wc -l)
if [ "$lcov_count" -eq 0 ]; then
    echo "Error: No lcov.info files found in $COVERAGE_REPORT_PATH"
    exit 1
else
    echo "Found $lcov_count lcov.info files in $COVERAGE_REPORT_PATH"
fi

echo "=== Zipping coverage reports ==="
zip_file="/app/coverage/$(date -d @$timestamp '+%Y-%m-%d')-$revision.zip"
zip -r "$zip_file" "$COVERAGE_REPORT_PATH"

echo "=== Coverage run completed ==="
endtime=$(date +%s)
elapsed=$((endtime - starttime))
echo "Total time: $elapsed seconds"

