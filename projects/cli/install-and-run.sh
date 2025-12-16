#!/bin/bash

cd /app/repo

npm install

set +e
npx nyc --reporter=lcov --reporter=text npm test
set -e