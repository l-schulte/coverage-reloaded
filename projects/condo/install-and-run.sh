#!/bin/bash
cd /app/repo

yarn install

set +e
if yarn workspaces foreach --help >/dev/null 2>&1; then
    echo "Using yarn workspaces foreach to run tests with coverage..."
    yarn workspaces foreach run test --coverage
else
    echo "Using yarn workspaces run to run tests with coverage..."
    yarn workspaces run test --coverage
fi
set -e