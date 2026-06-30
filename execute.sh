#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

# Disable IPv6 resolution — the host and containers lack IPv6 routing.
# This makes getent, curl, node, yarn, etc. all prefer IPv4 by default.
# The sysctl disables IPv6 on loopback and physical interfaces inside the
# container (harmless — no IPv6 connectivity anyway).
sysctl -w net.ipv6.conf.all.disable_ipv6=1 &>/dev/null || true

starttime=$(date +%s)
BASEDIR="/coverage_reloaded"
REPOPATH="$BASEDIR/repo"
export REPOPATH
cd "$REPOPATH"

export COVERAGE_REPORT_PATH="$BASEDIR/exported"
mkdir -p "$COVERAGE_REPORT_PATH"

export OUTPUT_PATH="$BASEDIR/coverage"
mkdir -p "$OUTPUT_PATH"

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

resolve_and_pin() {
    local hostname="$1"
    local max_attempts="${2:-8}"
    local backoff="${3:-2}"
    local ip=""

    for i in $(seq 1 $max_attempts); do
        ip=$(getent ahostsv4 "$hostname" 2>/dev/null | awk '/STREAM/ { print $1; exit }')
        if [ -n "$ip" ]; then
            echo "$hostname resolved to $ip after $i attempt(s)"
            grep -v " $hostname$" /etc/hosts > /tmp/hosts.tmp \
                && cp /tmp/hosts.tmp /etc/hosts \
                && rm -f /tmp/hosts.tmp
            echo "$ip $hostname" >> /etc/hosts
            echo "$hostname pinned in /etc/hosts"
            return 0
        fi
        local wait=$(( backoff ** (i - 1) ))
        echo "DNS resolution attempt $i/$max_attempts for $hostname failed — retrying in ${wait}s"
        sleep $wait
    done

    echo "FATAL: cannot resolve $hostname after $max_attempts attempts"
    return 1
}

# GitHub is deprecating the git:// protocol.
# Workaround: configure git to use https:// instead of git:// for github.com.
git config --global url."https://github.com/".insteadOf "git://github.com/"

IS_NPM_MAIN_PM=$([[ "$package_manager" == npm* ]] && echo "true" || echo "false")
export IS_NPM_MAIN_PM

IS_YARN_MAIN_PM=$([[ "$package_manager" == yarn* ]] && echo "true" || echo "false")
export IS_YARN_MAIN_PM

IS_PNPM_MAIN_PM=$([[ "$package_manager" == pnpm* ]] && echo "true" || echo "false")
export IS_PNPM_MAIN_PM

print_header 1 "Starting run-coverage.sh" "Revision: $revision"
echo "Commit date: $(date -d @$timestamp '+%Y-%m-%d %H:%M:%S')"
echo "Current date: $(date)"
echo "Timestamp: $timestamp"
echo "Package Manager: $package_manager"


print_header 2 "System Information"
uname -a

print_header 2 "Linux Distribution"
cat /etc/os-release

print_header 2 "Git Version"
git --version

print_header 2 "Python Version"
python --version

print_header 2 "CPU Information"
nproc

print_header 2 "Memory Information"
free -h

print_header 2 "Disk Information"
df -h

set -e
print_header 2 "Current Folder"
pwd

print_header 2 "Git Checkout"
git checkout "$revision"

print_header 2 "Node Version"
node --version

print_header 2 "Pinning registry hostnames"

resolve_and_pin "waypack"
resolve_and_pin "verdaccio"
resolve_and_pin "registry.npmjs.org"
resolve_and_pin "registry.yarnpkg.com"
resolve_and_pin "github.com"
resolve_and_pin "repo.yarnpkg.com"

print_header 2 "Setting up Package Managers"

WAYPACK_NPM_REGISTRY="http://waypack:3000/npm/$timestamp/"
export WAYPACK_NPM_REGISTRY
WAYPACK_YARN_REGISTRY="http://waypack:3000/yarn/$timestamp/"
export WAYPACK_YARN_REGISTRY
VERDACCIO_REGISTRY="http://verdaccio:4873/"
export VERDACCIO_REGISTRY

# Use Verdaccio directly for PM self-installs — WayPack is timestamp-scoped
# and won't have arbitrary PM versions like npm@8.0.0 cached.
npm config set registry "$VERDACCIO_REGISTRY"

# Corepack requires Node.js >= 16 (it uses ??= syntax). If Node is older,
# skip corepack and fall through to manual setup.
NODE_MAJOR=$(node --version | sed 's/v//' | cut -d. -f1)
if [ -x "$(command -v corepack)" ] && [ "$NODE_MAJOR" -ge 16 ] && grep -q '"packageManager"' package.json; then
    echo " --> Corepack setup for $package_manager"
    corepack enable
    corepack prepare "$package_manager" --activate
# Otherwise, setup manually.
else
    echo " --> Manual setup for $package_manager"
    # Disable corepack so it doesn't intercept package manager binaries
    corepack disable 2>/dev/null || true

    if [ "$IS_NPM_MAIN_PM" = "true" ]; then
        if [[ "$package_manager" == npm@* ]]; then
            specified_version="${package_manager#npm@}"
            npm install --no-fund -g "npm@$specified_version"
        fi
    elif [ "$IS_YARN_MAIN_PM" = "true" ]; then
        if [[ "$package_manager" == yarn@* ]]; then
            specified_version="${package_manager#yarn@}"
            major="${specified_version%%.*}"
            if [ "$major" -eq 1 ]; then
                npm uninstall -g yarn 2>/dev/null || true
                npm install --no-fund -g "yarn@$specified_version"
            else
                # For Yarn Berry (2+), try to use the repo's bundled yarn if available
                if [ -f ".yarnrc.yml" ]; then
                    BUNDLED_YARN=$(grep '^yarnPath:' .yarnrc.yml | awk '{print $2}')
                    if [ -n "$BUNDLED_YARN" ] && [ -f "$BUNDLED_YARN" ]; then
                        echo " --> Using repo-bundled yarn: $BUNDLED_YARN"
                        # Symlink the bundled yarn so 'yarn' command works globally
                        ln -sf "$(pwd)/$BUNDLED_YARN" /usr/local/bin/yarn
                        chmod +x /usr/local/bin/yarn
                    else
                        npm install --no-fund -g "yarn@$specified_version"
                    fi
                else
                    npm install --no-fund -g "yarn@$specified_version"
                fi
            fi
        else
            npm install -g yarn
        fi
        
        if command -v yarn &>/dev/null && yarn --version | grep -q "rc"; then
            set +e
            yarn set version latest
            set -e
        fi
    fi
    if [ "$IS_PNPM_MAIN_PM" = "true" ]; then
        npm install --no-fund -g pnpm
    fi
fi


if command -v yarn &>/dev/null; then
    export YARN_NETWORK_CONCURRENCY=1
fi

if command -v pnpm &>/dev/null; then
    export npm_config_network_concurrency=1
fi

export npm_config_maxsockets=1

# Switch back to WayPack for project dependency installs
npm config set registry "$WAYPACK_NPM_REGISTRY"

if [ "$IS_YARN_MAIN_PM" = "true" ]; then
    print_header 3 "Yarn Version After Setup"
    yarn --version
    IS_YARN_LEGACY=$(yarn --version | grep -q "^1\." && echo "true" || echo "false")
    echo "Legacy Yarn: $IS_YARN_LEGACY"

    if [ "$IS_YARN_LEGACY" = "true" ]; then
        yarn config set registry "$WAYPACK_YARN_REGISTRY"
        yarn config get registry
    else
        yarn config set unsafeHttpWhitelist --json '["waypack", "verdaccio"]'
        yarn config set npmRegistryServer "$WAYPACK_YARN_REGISTRY"
        yarn config get npmRegistryServer
    fi
    echo ""
fi

if [ "$IS_NPM_MAIN_PM" = "true" ]; then
    print_header 3 "NPM Version After Setup"
    npm --version
    npm config set registry "$WAYPACK_NPM_REGISTRY"
    npm config get registry
    echo ""
fi

if [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    print_header 3 "PNPM Version After Setup"
    pnpm --version
    pnpm config set registry "$WAYPACK_NPM_REGISTRY"
    pnpm config get registry
    echo ""
fi

print_header 2 "Cleaning package manager lock files"

# There may be a package-lock.json file with resolved URLs hardcoded to npmjs.org. Slow and potentially rate limited.
# Workaround 1: remove URLs
# Result: fails (TypeError [ERR_INVALID_ARG_TYPE]: The "paths[1]" argument must be of type string. Received undefined)
# [ -f "package-lock.json" ] && sed -i '/"resolved":/d' package-lock.json
# Workaround 2: replace URLs with waypack URL (https://registry.npmjs.org/)
# Result: works
match_patterns=('package-lock.json' '*/package-lock.json')
ignore_patterns=('*/node_modules/*')
execute_function='sed -i "s#\"resolved\": \"https://registry.npmjs.org/#\"resolved\": \"'"$WAYPACK_NPM_REGISTRY"'#g" {}'
process_files "$execute_function"

# yarn.lock files often contain resolved URLs to central repositories.
# Workaround 1: remove those lines to let yarn resolve them via the configured registry (waypack & verdaccio).
# [ -f "yarn.lock" ] && sed -i '/^  resolved/d' yarn.lock
# Workaround 2: replace URLs with waypack URL (https://registry.yarnpkg.com/)
match_patterns=('yarn.lock' '*/yarn.lock')
ignore_patterns=('*/node_modules/*')
execute_function='sed -i "s|resolved \"https://registry.yarnpkg.com/|resolved \"'"$WAYPACK_YARN_REGISTRY"'|g" {}'
process_files "$execute_function"
# execute_function='sed -i "/^[[:space:]]*integrity /d" {}'
# process_files "$execute_function"

# pnpm-lock.yaml files also contain resolved URLs to central repositories.
# Workaround: replace URLs with waypack URL (https://registry.npmjs.org/)
match_patterns=('pnpm-lock.yaml' '*/pnpm-lock.yaml')
ignore_patterns=('*/node_modules/*')
execute_function='sed -i "s|https://registry.npmjs.org/|'"$WAYPACK_NPM_REGISTRY"'|g" {}'
process_files "$execute_function"

echo ""



print_header 1 "Calling install-and-run.sh"

(sleep 5220s && echo "WARNING: 90 minute timeout for install-and-run.sh about to apply") &
TIMEOUT_PID=$!

set +e
timeout 5400s bash ../install-and-run.sh
INSTALL_AND_RUN_EXIT=$?
set -e

# Kill the background warning process if it's still running
kill $TIMEOUT_PID 2>/dev/null || true

if [ $INSTALL_AND_RUN_EXIT -eq 2 ]; then
    print_header 4 "NOT APPLICABLE: install-and-run.sh exited with code 2 — no test infrastructure at this commit"

    # Write a .not_applicable marker file with commit info and full log
    not_applicable_file="$OUTPUT_PATH/${timestamp}_${revision}.not_applicable"
    {
        echo "Commit: $revision"
        echo "Timestamp: $timestamp"
        echo "Exit code: 2"
        echo "---"
        # Capture the full log from the install-and-run run (replay from log if available)
        # The log is already captured by the docker_run infrastructure; write a summary here.
    } > "$not_applicable_file"

    # Also capture the full output by re-running with logging, but since we're in the
    # docker container, we can write what we know and let the Python side append the log.
    print_header 4 "Wrote .not_applicable marker: $not_applicable_file"
    exit 2
fi

if [ $INSTALL_AND_RUN_EXIT -ne 0 ]; then
    if [ $INSTALL_AND_RUN_EXIT -eq 124 ]; then
        print_header 4 "ERROR: install-and-run.sh timed out after 5400s (90 minutes)"
    else
        print_header 4 "ERROR: install-and-run.sh failed with exit code $INSTALL_AND_RUN_EXIT"
    fi
    exit $INSTALL_AND_RUN_EXIT
fi

print_header 4 "install-and-run.sh completed successfully"

print_header 2 "Collecting individual coverage reports"

# Instead of merging (which causes function data mismatch warnings when
# combining coverage from different instrumenters like Jest and Cypress),
# we copy each lcov file to the output with a unique name.
#
# Each commit gets its own directory: {timestamp}_{revision}/
# Inside: {test_type}__{subdir}.lcov and {test_type}__{subdir}.exit_code
#
# Examples:
#   1700000000_80af8e6c/
#     ├── test_coverage__packages_vuetify.lcov
#     ├── test_coverage__packages_vuetify.exit_code
#     ├── cypress__packages_vuetify_coverage_cypress.lcov
#     └── cypress__packages_vuetify_coverage_cypress.exit_code

prefix="${timestamp}_${revision}"

# ── Re-run safety: clean up any stale directory or files for this commit ──
if [ -d "$OUTPUT_PATH/$prefix" ]; then
    print_header 4 "NOTICE: Removing stale output directory for re-run: $prefix"
    rm -rf "$OUTPUT_PATH/$prefix"
fi
# Also remove any stale flat files from a previous naming convention
rm -f "$OUTPUT_PATH/${prefix}"__*.lcov "$OUTPUT_PATH/${prefix}"__*.exit_code

commit_dir="$OUTPUT_PATH/$prefix"
mkdir -p "$commit_dir"

mapfile -t lcov_files < <(find "$COVERAGE_REPORT_PATH" \( -name "*.lcov.info" -o -name "lcov.info" \) -size +0)

if [[ ${#lcov_files[@]} -eq 0 ]]; then
    echo "Error: No lcov files found in $COVERAGE_REPORT_PATH"
    exit 1
fi

for f in "${lcov_files[@]}"; do
    # Get the relative path within COVERAGE_REPORT_PATH
    rel="${f#$COVERAGE_REPORT_PATH/}"
    # Remove .lcov.info or .info suffix
    stem="${rel%.lcov.info}"
    stem="${stem%.info}"
    # Sanitize: replace / and - with _
    safe_stem="${stem//\//_}"
    safe_stem="${safe_stem//-/_}"

    dest="$commit_dir/${safe_stem}.lcov"
    cp "$f" "$dest"
    echo "  [OK]  $(basename "$f") → $prefix/${safe_stem}.lcov"

    # Also copy the corresponding exit code file if it exists
    exit_code_file="$(dirname "$f")/$(basename "${rel%.lcov.info}").exit_code"
    if [ ! -f "$exit_code_file" ]; then
        # Fallback: try the stem without .info suffix
        exit_code_file="$(dirname "$f")/$(basename "${rel%.info}").exit_code"
    fi
    if [ -f "$exit_code_file" ]; then
        exit_code_value=$(cat "$exit_code_file")
        cp "$exit_code_file" "$commit_dir/${safe_stem}.exit_code"
        echo "  [OK]  exit_code → $prefix/${safe_stem}.exit_code (value: $exit_code_value)"
    fi
done



endtime=$(date +%s)
elapsed=$((endtime - starttime))
print_header 1 "Coverage run completed" "Revision: $revision" "Total time: $elapsed seconds"
