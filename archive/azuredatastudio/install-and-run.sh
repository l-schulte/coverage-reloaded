#!/bin/bash
cd /app/repo

# The postinstall script downloads files from the following URLs:
# - https://github.com/Microsoft/sqltoolsservice/releases/download/4.3.0.15/microsoft.sqltools.servicelayer-rhel-x64-net6.0.tar.gz
#   -> defined in multiple config files... with multiple versions
#     - extensions/mssql/config.json
#     - extensions/azuremonitor/config.json
#     - extensions/sql-migration/config.json
#     - extensions/kusto/config.json
# - https://sqlopsextensions.blob.core.windows.net/tools/ssmsmin/15.0.18124.0/SsmsMin-15.0.18124.0-win-x64.zip
#   -> defined in extensions/admin-tool-ext-win/config.json 
# - https://sqlopsextensions.blob.core.windows.net/tools/ssmsmin/16.0.19061.0/SsmsMin-16.0.19061.0-win-x64.zip
#   -> defined in extensions/admin-tool-ext-win/config.json 
# Workaround: we use the waypack machine to proxy those requests
sed -i 's|https://github.com/Microsoft/sqltoolsservice/releases/download/|http://waypack:3000/request/https://github.com/Microsoft/sqltoolsservice/releases/download/|g' extensions/mssql/config.json
sed -i 's|https://github.com/Microsoft/sqltoolsservice/releases/download/|http://waypack:3000/request/https://github.com/Microsoft/sqltoolsservice/releases/download/|g' extensions/azuremonitor/config.json
sed -i 's|https://github.com/Microsoft/sqltoolsservice/releases/download/|http://waypack:3000/request/https://github.com/Microsoft/sqltoolsservice/releases/download/|g' extensions/sql-migration/config.json
sed -i 's|https://github.com/Microsoft/sqltoolsservice/releases/download/|http://waypack:3000/request/https://github.com/Microsoft/sqltoolsservice/releases/download/|g' extensions/kusto/config.json
sed -i 's|https://sqlopsextensions.blob.core.windows.net|http://waypack:3000/request/https://sqlopsextensions.blob.core.windows.net|g' extensions/admin-tool-ext-win/config.json

# Atom.io is no longer available and electronjs.org is unreliable
# Workaround: use the custom_cache feature of waypack to cache electron headers
sed -i 's|disturl "https://atom.io/download/electron"|disturl "http://waypack:3000/request/https://nodejs.org/download/release/"|g' .yarnrc

Xvfb :99 -screen 0 1024x768x16 &
export DISPLAY=:99
export CHROMIUM_FLAGS="--no-sandbox --disable-setuid-sandbox"

python ../restore_vscode.py
ls -la .vscode-test/

set -e

# If playwright is not installed manually, it will try to do it during tests, which fails due to unavailable urls, i.e.,
# https://playwright.azureedge.net/builds/firefox/1205/firefox-ubuntu-18.04.zip
echo "-> Installing Playwright browsers..."
yarn cache clean --force
yarn add playwright --no-lockfile --update-checksums

# Requires a non-existing dependency (github-releases-ms, was deleted from registry)
# Workaround: providing the file (github-releases-ms-0.5.0.tgz) in the waypack machine
# Integrity checks fail for this file.
# Workaround: clean cache with yarn cache clean disable integrity checks for yarn installs by adding --update-checksums
echo "-> Installing dependencies via yarn..."
yarn cache clean --force
yarn install --update-checksums


# The test execution fails if the build output is missing... this slows things down.
echo "-> Compiling the project via yarn..."
yarn compile

set +e

# There seems to be no way to control the output format/location
echo "-> Running tests with coverage via bash ./scripts/test.sh --coverage ..."
bash ./scripts/test.sh --coverage

set -e

bash ../find-and-move-lcov.sh

python ../store_vscode.py