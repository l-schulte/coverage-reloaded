#!/bin/bash
cd /app/repo

npm ci --no-fund

set +e
if grep -q "test:coverage" package.json; then
    echo "Running tests with coverage script..."
    npm run test:coverage -- --coverage.enabled=true --coverage.reporter=lcov
else
    echo "Running unit tests with coverage..."
    npm run test:unit -- --coverage
fi
set -e