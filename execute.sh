#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

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

print_header 2 "Setting up Package Managers"

WAYPACK_NPM_REGISTRY="http://waypack:3000/npm/$timestamp/"
export WAYPACK_NPM_REGISTRY
WAYPACK_YARN_REGISTRY="http://waypack:3000/yarn/$timestamp/"
export WAYPACK_YARN_REGISTRY

npm config set registry "$WAYPACK_NPM_REGISTRY"

if [ -x "$(command -v corepack)" ] && grep -q '"packageManager"' package.json; then
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
                yarn set version "$specified_version"
            fi
        else
            npm install -g yarn
        fi
        
        if yarn --version | grep -q "rc"; then
            set +e
            yarn set version latest
            set -e
        fi
    fi
    if [ "$IS_PNPM_MAIN_PM" = "true" ]; then
        npm install --no-fund -g pnpm
    fi
fi

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
timeout 5400s bash ../install-and-run.sh



print_header 2 "Counting coverage reports"


# Find all lcov.info files in the coverage directory
lcov_count=$(find "$COVERAGE_REPORT_PATH" -name "*.lcov.info" -o -name "lcov.info" | wc -l)
lcov_count_valid=$(find "$COVERAGE_REPORT_PATH" -name "*.lcov.info" -o -name "lcov.info" -size +0 | wc -l)
if [ "$lcov_count" -eq 0 ]; then
    echo "Error: No lcov.info files found in $COVERAGE_REPORT_PATH"
    exit 1
else
    echo "--> Found $lcov_count lcov.info files in $COVERAGE_REPORT_PATH ($lcov_count_valid with size > 0)"
fi


print_header 2 "Merging coverage reports"

mapfile -t lcov_files < <(find "$COVERAGE_REPORT_PATH" \( -name "*.lcov.info" -o -name "lcov.info" \) -size +0)

if [[ ${#lcov_files[@]} -eq 1 ]]; then
    echo "Single lcov file found, copying directly to merged.lcov"
    cp "${lcov_files[0]}" "$COVERAGE_REPORT_PATH/merged.lcov"
else
    echo "Merging ${#lcov_files[@]} lcov files"
    lcov_args=()
    for f in "${lcov_files[@]}"; do
        lcov_args+=(--add-tracefile "$f")
    done
    lcov "${lcov_args[@]}" \
        --output-file "$COVERAGE_REPORT_PATH/merged.lcov" \
        --rc lcov_branch_coverage=1
fi


print_header 2 "Reporting coverage to coverageSHARK"


mv "$COVERAGE_REPORT_PATH/merged.lcov" "$OUTPUT_PATH/$revision.lcov"



endtime=$(date +%s)
elapsed=$((endtime - starttime))
print_header 1 "Coverage run completed" "Revision: $revision" "Total time: $elapsed seconds"
