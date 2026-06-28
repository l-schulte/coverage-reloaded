#!/bin/bash

# Helper functions for patching broken GitHub dependency URLs in package.json
# and package-lock.json. Sourced by install-and-run.sh.

# Replace a git dependency in package.json with an npm version range.
# Usage: patch_git_dep_json <package_name> <old_url_pattern> <npm_version>
patch_git_dep_json() {
    local pkg="$1" old_url="$2" version="$3"
    if grep -q "$old_url" package.json 2>/dev/null; then
        print_header 4 "Patching $pkg URL in package.json"
        sed -i 's|"'"$pkg"'": "[^"]*'"$old_url"'[^"]*"|"'"$pkg"'": "'"$version"'"|g' package.json
    fi
}

# Remove the "resolved" line for a package in package-lock.json's packages section,
# and replace the dependency entry URL with an npm version range.
# Usage: patch_git_dep_lock <package_name> <old_url_pattern> <npm_version>
patch_git_dep_lock() {
    local pkg="$1" old_url="$2" version="$3"
    if [ ! -f package-lock.json ]; then return; fi
    if ! grep -q "$old_url" package-lock.json 2>/dev/null; then return; fi
    print_header 4 "Patching $pkg URL in package-lock.json"
    # Remove the "resolved" line inside the packages section for this package
    sed -i '/"node_modules\/'"$pkg"'": {/,/^[[:space:]]*}/{
      /"resolved":/d
    }' package-lock.json
    # Replace the dependency entry URL with the npm version
    sed -i 's|"'"$pkg"'": "[^"]*'"$old_url"'[^"]*"|"'"$pkg"'": "'"$version"'"|g' package-lock.json
}

# Simple string replacement in both package.json and package-lock.json.
# Usage: patch_git_dep_simple <package_name> <old_string> <new_string>
patch_git_dep_simple() {
    local pkg="$1" old_str="$2" new_str="$3"
    if grep -q "$old_str" package.json 2>/dev/null; then
        print_header 4 "Patching $pkg URL in package.json"
        sed -i 's|'"$old_str"'|'"$new_str"'|g' package.json
    fi
    if [ -f package-lock.json ] && grep -q "$old_str" package-lock.json 2>/dev/null; then
        print_header 4 "Patching $pkg URL in package-lock.json"
        sed -i 's|'"$old_str"'|'"$new_str"'|g' package-lock.json
    fi
}
