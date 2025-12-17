
#!/bin/bash
cd /app/repo

Xvfb :99 -screen 0 1024x768x16 &
export DISPLAY=:99
export CHROMIUM_FLAGS="--no-sandbox --disable-setuid-sandbox"

mkdir -p /app/repo/.vscode-test/vscode-linux-x64-1.107.0
tar -xzf /app/vscode-linux-x64-1.107.0.tar.gz -C /app/repo/.vscode-test/vscode-linux-x64-1.107.0 --strip-components=1

npm install

set +e
# Notes:
# There are E2E test, and also integration tests.
# They require a display to run...
# npm run testE2E
npm run test --coverage --no-bail
set -e
