#!/bin/bash
cd /app/repo

yarn install

set +e
if yarn workspaces foreach --help >/dev/null 2>&1; then
    yarn workspaces foreach run test --coverage
else
    yarn workspaces run test --coverage
fi
set -e