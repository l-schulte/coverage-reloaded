#!/bin/bash

# -------------------------------------------------------------
# ATTENTION! ONLY MODIFY THE ORIGINAL
# THIS WILL BE COPIED TO EACH PROJECT'S FOLDER AUTOMATICALLY
# -------------------------------------------------------------

cd /app/repo
starttime=$(date +%s)

echo "=== Starting run-coverage.sh ==="
echo "Revision: $revision"
echo "Commit date: $(date -d @$timestamp)"
echo "Timestamp: $timestamp"
echo "Package Manager: $package_manager"
echo "=== System Information ==="
uname -a
echo ""
echo "=== Linux Distribution ==="
cat /etc/os-release
echo ""
echo "=== Node Version ==="
node --version
echo ""
echo "=== NPM Version ==="
npm --version
echo ""
echo "=== Yarn Version ==="
yarn --version
IS_YARN_LEGACY=$(yarn --version | grep -q "^1\." && echo "true" || echo "false")
export IS_YARN_LEGACY
echo "Legacy Yarn: $IS_YARN_LEGACY"
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

git checkout "$revision"

echo "Setting npm registry to Waypack..."
npm config set registry "http://waypack:3000/npm/$timestamp/"

if [ "$IS_YARN_LEGACY" = "true" ]; then
    echo "Setting yarn legacy registry to Waypack..."
    yarn config set registry "http://waypack:3000/npm/$timestamp/"
else
    echo "Setting yarn modern registry to Waypack..."
    yarn config set unsafeHttpWhitelist "waypack"
    yarn config set npmRegistryServer "http://waypack:3000/npm/$timestamp/"
fi

# echo "Setting pnpm registry to Waypack..."
# pnpm config set registry "http://waypack:3000/npm/$timestamp/"

echo "Installing dependencies and running tests with coverage..."

timeout 5400s bash ../install-and-run.sh


PATTERNS=('coverage/**' 'packages/**/coverage/**' "apps/**/coverage/**")
IGNORE_PATTERNS=('*/node_modules/*')

# Build the find command's ignore arguments
ignore_args=()
for ignore in "${IGNORE_PATTERNS[@]}"; do
    ignore_args+=(-not -path "$ignore")
done

lcov_count=0
for pattern in "${PATTERNS[@]}"; do
    lcov_count=$((lcov_count + $(find . -path "./$pattern" -name "lcov.info" "${ignore_args[@]}" | wc -l)))
done

if [ "$lcov_count" -eq 0 ]; then
    echo "Error: No lcov.info files found in any of the specified paths"
    exit 1
fi

zip_file="../coverage/$(date -d @$timestamp '+%Y-%m-%d')-$revision.zip"
zip -r "$zip_file" . -i "${PATTERNS[@]}" -x "${IGNORE_PATTERNS[@]}"

echo "=== Coverage run completed ==="
endtime=$(date +%s)
elapsed=$((endtime - starttime))
echo "Total time: $elapsed seconds"

