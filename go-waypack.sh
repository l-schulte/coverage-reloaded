#!/bin/bash

revision="$revision"
timestamp="$timestamp"
starttime=$(date +%s)

echo "=== Starting npm_and_run.sh ==="
echo "$(date -d @$timestamp)"
echo "$revision - $timestamp"
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

npm set registry http://waypack:3000/npm/$timestamp/
npm config set registry http://waypack:3000/npm/$timestamp/
yarn config set registry http://waypack:3000/yarn/$timestamp/

bash ./../run-coverage.sh