#!/bin/bash
cd /app/repo

npm ci --no-fund


set +e
if grep -q "test:coverage" package.json; then
    npm run test:coverage -- --coverage.enabled=true --coverage.reporter=lcov
else
    npm run test:unit -- --coverage
fi
set -e

