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

zip -r "../coverage/$(date -d @$timestamp '+%Y-%m-%d')-$revision.zip" . -i 'coverage/**' 'packages/**/coverage/**' 'apps/**/coverage/**'
[ -s "../coverage/$(date -d @$timestamp '+%Y-%m-%d')-$revision.zip" ] || { echo "Error: zip file is empty"; exit 1; }

echo "=== Coverage run completed ==="
endtime=$(date +%s)
elapsed=$((endtime - starttime))
echo "Total time: $elapsed seconds"

