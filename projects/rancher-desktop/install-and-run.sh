#!/bin/bash

cd /coverage_reloaded/repo

npm install -g npm
npm ci

set +e

npm test --coverage --coverageReporters=lcov --coverageDirectory="$COVERAGE_REPORT_PATH"

set -e