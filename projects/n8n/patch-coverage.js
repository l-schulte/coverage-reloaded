'use strict';

// n8n coverage patch — appends runner-specific coverage flags to every `test*`
// script so the root `test` dispatch (lerna/turbo) collects lcov per package.
// Also adds --no-bail/--continue to the root dispatch (tests must never bail)
// and neutralises the e2e playwright `test` script.

var fs = require('fs');
var path = require('path');

function readJson(p) {
	return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function writeJson(p, obj) {
	fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n');
}

// Script names that are candidates for coverage patching. We only RUN the root
// `test`, but sub-scripts it forwards to (cli: test -> test:sqlite;
// editor-ui: test -> test:unit) must be patched as well. e2e / watch / dev /
// db-server suites are never part of the root `test` dispatch and are skipped.
var SKIP_TOKENS = ['e2e', 'watch', 'dev', 'container', 'flaky', 'win', 'changed', 'local',
	'performance', 'benchmark', 'workflows', 'migration', 'postgres', 'mysql', 'mariadb', 'coverage'];

function isPatchableScriptName(name) {
	if (name.indexOf('test') !== 0) return false;
	for (var i = 0; i < SKIP_TOKENS.length; i++) {
		if (name.indexOf(SKIP_TOKENS[i]) >= 0) return false;
	}
	return true;
}

function patchScript(s) {
	if (typeof s !== 'string' || s.trim() === '') return s;
	if (s.indexOf('playwright') >= 0) {
		// E2E suite must never run as part of the root `test` dispatch.
		return 'node -e "console.log(\'[patch-coverage] skipping playwright e2e suite\'); process.exit(0)"';
	}
	if (s.indexOf('jest') >= 0) {
		s = s.replace(/--no-coverage/g, '');
		return s + ' --coverage --coverageReporters=lcov --maxWorkers=2';
	}
	if (s.indexOf('vitest') >= 0) {
		return s + ' --coverage reporters=lcov';
	}
	if (s.indexOf('vue-cli-service') >= 0) {
		return s + ' --coverage --coverageReporters=lcov';
	}
	return s;
}

function patchRoot(pkg) {
	var s = (pkg.scripts || {}).test || '';
	if (/lerna run test/.test(s)) {
		if (s.indexOf('--no-bail') < 0) pkg.scripts.test = s + ' --no-bail --concurrency=2';
	} else if (/turbo run test/.test(s)) {
		if (s.indexOf('--continue') < 0) {
			pkg.scripts.test = s.replace(/turbo run test/, 'turbo run test --continue --concurrency=2');
		}
	}
}

// Walk the whole repo (excluding install/build output) and collect every
// package.json, so no workspace is ever missed regardless of layout changes
// across the 2020-2025 timeframe (packages/, packages/@n8n/, packages/@n8n_io/,
// packages/frontend/**, packages/modules/**, cypress/, ...). Directories with
// no package.json or with only non-test scripts are no-ops in the main loop.
var dirs = [];
var SKIP_DIRS = ['node_modules', '.git', 'dist'];
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
	var isRoot = (dir === '.');
	var didPatch = false;

	if (isRoot) {
		if (scripts.test) {
			var before = scripts.test;
			patchRoot(pkg);
			if (scripts.test !== before) didPatch = true;
		}
	} else {
		var hasVueCli = false;
		Object.keys(scripts).forEach(function (name) {
			if (!isPatchableScriptName(name)) return;
			var def = scripts[name];
			if (typeof def !== 'string') return;
			if (def.indexOf('vue-cli-service') >= 0) hasVueCli = true;
			var patched = patchScript(def);
			if (patched !== def) {
				scripts[name] = patched;
				didPatch = true;
			}
		});
		// vue-cli-service test:unit wraps jest; the reporter flag may not be forwarded,
		// so force lcov via the package.json "jest" key instead.
		if (hasVueCli && typeof pkg.jest === 'object' && pkg.jest !== null && !Array.isArray(pkg.jest)) {
			pkg.jest.coverageReporters = ['lcov'];
			didPatch = true;
		} else if (hasVueCli) {
			pkg.jest = { coverageReporters: ['lcov'] };
			didPatch = true;
		}
	}

	if (didPatch) {
		writeJson(pkgFile, pkg);
		changed.push(dir);
	}
}

console.log('Patched package.json files (' + changed.length + '): ' + changed.join(', '));
