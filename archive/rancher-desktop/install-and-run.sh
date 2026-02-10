#!/bin/bash

cd /coverage_reloaded/repo

# Go through recursively through all files and folders in the scripts folder and replace https://github.com/ and https://raw.githubusercontent.com/
# with http://waypack:3000/request/https://github.com/ and http://waypack:3000/request/https://raw.githubusercontent.com/ respectively,
# so that they are routed through Waypack.
# 
# Problem: download of https://raw.githubusercontent.com/moby/moby/master/docs/api/....yaml fails, 404. The file path moved and is now 
# https://raw.githubusercontent.com/moby/moby/master/api/docs/
# Solution: replace all occurrences in all files in the scripts folder, so that the new path is also covered.
#
# Problem: downloads from https://dl.k8s.io/ fail (timeout).
# Solution: route these requests through Waypack as well.
for file in $(find ./scripts -type f); do
    sed -i 's|https://raw.githubusercontent.com/moby/moby/master/docs/api/|https://raw.githubusercontent.com/moby/moby/master/api/docs/|g' "$file"
    sed -i 's|https://github.com/|http://waypack:3000/request/https://github.com/|g' "$file"
    sed -i 's|https://raw.githubusercontent.com/|http://waypack:3000/request/https://raw.githubusercontent.com/|g' "$file"
    sed -i 's|https://dl.k8s.io/|http://waypack:3000/request/https://dl.k8s.io/|g' "$file"
done

# Problem: postinstaller looks for tar in /usr/bin/tar, but it is located in /bin/tar in the container.
# Solution: create a symlink from /usr/bin/tar to /bin/tar.
ln -s /bin/tar /usr/bin/tar

npm ci

# set +e

npx --registry=$WAYPACK_NPM_REGISTRY nyc \
    --reporter=lcov \
    --report-dir="$COVERAGE_REPORT_PATH" \
    npm run test:unit:jest

# set -e