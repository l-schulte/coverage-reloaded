#!/bin/bash
cd /app/repo

yarn install

set +e
npx lerna run test --concurrency 1 -- --coverage
set -e