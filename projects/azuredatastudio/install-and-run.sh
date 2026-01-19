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
# Workaround: we provide the SSmsMin files in the waypack machine. The sqltools.servicelayer has too many versions, so they will need 
#             to be downloaded from the internet.
# Specifics:  "https://sqlopsextensions.blob.core.windows.net/tools/ssmsmin/{#version#}/{#fileName#}" -> "http://waypack:3000/local/{#filename#}"
sed -i 's|https://sqlopsextensions.blob.core.windows.net/tools/ssmsmin/{#version#}/{#fileName#}|http://waypack:3000/local/{#fileName#}|g' extensions/admin-tool-ext-win/config.json

Xvfb :99 -screen 0 1024x768x16 &
export DISPLAY=:99
export CHROMIUM_FLAGS="--no-sandbox --disable-setuid-sandbox"

python ../restore_vscode.py
ls -la .vscode-test/

# Requires a non-existing dependency (github-releases-ms, was deleted from registry)
# Workaround: providing the file (github-releases-ms-0.5.0.tgz) in the waypack machine
# Integrity checks fail for this file.
# Workaround: disable integrity checks for yarn installs by adding --update-checksums
yarn install --silent --update-checksums

yarn compile

set +e

bash ./scripts/test.sh --coverage

set -e

bash ../find-and-move-lcov.sh

python ../store_vscode.py