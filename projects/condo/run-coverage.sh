#!/bin/bash

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

cd /app/repo
git checkout "$revision"

npm config set registry "http://waypack:3000/npm/$timestamp/"
yarn config set registry "http://waypack:3000/yarn/$timestamp/"
# pnpm config set registry "http://waypack:3000/npm/$timestamp/"

set -e

cd /app/repo

yarn install

set +e
yarn workspaces foreach run test --coverage
set -e

PATTERNS=('coverage/**' 'packages/**/coverage/**' "apps/**/coverage/**")

lcov_count=0
for pattern in "${PATTERNS[@]}"; do
    lcov_count=$((lcov_count + $(find . -path "./$pattern" -name "lcov.info" | wc -l)))
done

if [ "$lcov_count" -eq 0 ]; then
    echo "Error: No lcov.info files found in any of the specified paths"
    exit 1
fi

zip_file="../coverage/$(date -d @$timestamp '+%Y-%m-%d')-$revision.zip"
zip -r "$zip_file" . -i "${PATTERNS[@]}"

echo "=== Coverage run completed ==="
endtime=$(date +%s)
elapsed=$((endtime - starttime))
echo "Total time: $elapsed seconds"

