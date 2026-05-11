#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

cd /coverage_reloaded/repo

print_header 2 "Installing dependencies"

npm install --no-fund --include=dev --unsafe-perm --legacy-peer-deps --maxsockets=22

print_header 2 "Running tests"
set +e

node Makefile.js mocha

bash ../find-and-move-lcov.sh mocha
    
set -e