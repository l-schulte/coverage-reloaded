#!/bin/bash

set -e
cd /coverage_reloaded/repo

yarn install

# set +e

yarn run ci --coverage --coverageDirectory="$COVERAGE_REPORT_PATH"

# set -e