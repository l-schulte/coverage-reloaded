'use strict';

// apollo-client coverage patch
//
// Patches test scripts to collect lcov coverage. The project uses:
// - jest for unit tests (Core Tests, ReactDOM 17/18/19, RxJS min, GraphQL 16)
// - vitest for codemod tests (scripts/codemods/ac3-to-ac4)
// - Playwright for integration tests (excluded)
//
// Strategy: patch the `coverage` script to use lcov reporter, and patch
// any vitest test scripts to use lcov as well.

var fs = require('fs');
var path = require('path');

function readJson(p) {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function writeJson(p, obj) {
    fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n');
}

// Script names to skip (e2e, watch, debug, etc.)
var SKIP_TOKENS = ['e2e', 'watch', 'dev', 'debug', 'playwright', 'memory', 'codegen'];

function isPatchableScriptName(name) {
    if (name.indexOf('test') !== 0 && name.indexOf('coverage') !== 0) return false;
    for (var i = 0; i < SKIP_TOKENS.length; i++) {
        if (name.indexOf(SKIP_TOKENS[i]) >= 0) return false;
    }
    return true;
}

function patchScript(name, s) {
    if (typeof s !== 'string' || s.trim() === '') return s;

    // Skip playwright e2e tests
    if (s.indexOf('playwright') >= 0) {
        return 'node -e "console.log(\'[patch-coverage] skipping playwright e2e suite\'); process.exit(0)"';
    }

    // For coverage script: ensure lcov reporter is used
    if (name === 'coverage') {
        // Add --coverageReporters=lcov if not already present
        if (s.indexOf('--coverageReporters') < 0) {
            return s + ' --coverageReporters=lcov';
        }
        return s;
    }

    // For jest test scripts: add coverage flags
    if (s.indexOf('jest') >= 0) {
        // Don't double-patch if already has coverage
        if (s.indexOf('--coverage') >= 0) {
            return s;
        }
        return s + ' --coverage --coverageReporters=lcov --maxWorkers=2';
    }

    // For vitest test scripts: add coverage flags
    if (s.indexOf('vitest') >= 0) {
        if (s.indexOf('--coverage') >= 0) {
            return s;
        }
        return s + ' --coverage --coverageReporters=lcov';
    }

    return s;
}

// Walk the repo and patch package.json files
var dirs = [];
var SKIP_DIRS = ['node_modules', '.git', 'dist', 'coverage'];

function walk(dir) {
    var pkgFile = path.join(dir, 'package.json');
    if (fs.existsSync(pkgFile)) dirs.push(dir);
    var entries;
    try {
        entries = fs.readdirSync(dir);
    } catch (e) {
        return;
    }
    for (var i = 0; i < entries.length; i++) {
        var name = entries[i];
        if (SKIP_DIRS.indexOf(name) >= 0) continue;
        var full = path.join(dir, name);
        var st;
        try {
            st = fs.statSync(full);
        } catch (e) {
            continue;
        }
        if (st.isDirectory()) walk(full);
    }
}

walk('.');

var changed = [];
for (var d = 0; d < dirs.length; d++) {
    var dir = dirs[d];
    var pkgFile = path.join(dir, 'package.json');
    if (!fs.existsSync(pkgFile)) continue;
    var pkg = readJson(pkgFile);
    var scripts = pkg.scripts || {};
    var didPatch = false;

    Object.keys(scripts).forEach(function (name) {
        if (!isPatchableScriptName(name)) return;
        var def = scripts[name];
        if (typeof def !== 'string') return;
        var patched = patchScript(name, def);
        if (patched !== def) {
            scripts[name] = patched;
            didPatch = true;
        }
    });

    if (didPatch) {
        writeJson(pkgFile, pkg);
        changed.push(dir);
    }
}

console.log('Patched package.json files (' + changed.length + '): ' + changed.join(', '));
