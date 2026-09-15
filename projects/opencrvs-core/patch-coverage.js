'use strict';

// opencrvs-core coverage patch — appends runner-specific coverage flags to every
// `test*` script so the root `lerna run test` dispatch collects lcov per package.
// Also adds --no-bail to the root dispatch (tests must never bail), raises the
// Node heap for the memory-hungry coverage reports, and neutralises e2e/storybook
// test scripts.
//
// Vitest handling is version-aware:
//   - vitest 0.x (login, client): bare `--coverage` + `--coverage.reporter=lcov`
//     collide in the 0.25 CAC parser (dotted key set on boolean true), and
//     `--maxWorkers` does not exist in 0.x. We use the dotted
//     `--coverage.enabled=true --coverage.reporter=lcov` form and cap
//     parallelism with the VITEST_MAX_THREADS / VITEST_MIN_THREADS env vars
//     (--no-threads would break per-file isolation: shared localStorage mocks
//     leak across test files).
//   - vitest >= 1 (events): vitest 2.x requires the separate provider package
//     `@vitest/coverage-v8`. We keep `--coverage --coverage.reporter=lcov
//     --maxWorkers=2` and record the provider (pinned to the vitest version
//     resolved from the lockfile) in `.coverage-providers.json`; install-and-run.sh
//     installs it out-of-tree so the frozen workspace install is not disturbed.

var fs = require('fs');
var path = require('path');

// Packages (notably @opencrvs/client) hardcode `NODE_OPTIONS=--max_old_space_size=8000`
// on their test scripts, which overrides the heap size exported by
// install-and-run.sh. That inline value is not enough to generate the c8
// coverage report for the client workspace, so the process aborts (SIGABRT,
// exit 134) after all tests pass and no client lcov is written. Rewrite any
// inline max-old-space-size to this value so the override can no longer shrink
// the heap. Keep in sync with install-and-run.sh.
var HEAP_MB = 16384;

function readJson(p) {
	return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function writeJson(p, obj) {
	fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n');
}

// Script names that are candidates for coverage patching. Only scripts whose
// name starts with `test` and does not contain any of these tokens are patched.
// e2e / watch / dev / compilation / lint / storybook suites are never part of
// the root `test` dispatch and are skipped.
var SKIP_TOKENS = [
	'e2e', 'watch', 'dev', 'compilation', 'lint', 'storybook',
	'coverage', 'open', 'chromatic', 'preview', 'serve'
];

function isPatchableScriptName(name) {
	if (name.indexOf('test') !== 0) return false;
	for (var i = 0; i < SKIP_TOKENS.length; i++) {
		if (name.indexOf(SKIP_TOKENS[i]) >= 0) return false;
	}
	return true;
}

// Major version of the vitest declared by a package, or null if vitest is not
// a declared dependency.
function getVitestMajor(pkg) {
	var spec = (pkg.devDependencies || {}).vitest || (pkg.dependencies || {}).vitest;
	if (!spec) return null;
	var m = String(spec).match(/(\d+)\./);
	if (!m) return null;
	return parseInt(m[1], 10);
}

// Resolve the exact vitest version that the committed yarn.lock pins for the
// given spec (e.g. "^2.1.5" -> "2.1.5"). Returns null when unavailable.
function getLockfileVitestVersion(spec) {
	if (!spec) return null;
	var lockPath = path.join(process.cwd(), 'yarn.lock');
	if (!fs.existsSync(lockPath)) return null;
	var lines;
	try {
		lines = fs.readFileSync(lockPath, 'utf8').split('\n');
	} catch (e) {
		return null;
	}
	var target = 'vitest@' + spec;
	var inBlock = false;
	for (var i = 0; i < lines.length; i++) {
		var line = lines[i];
		if (!line) continue;
		if (line[0] === ' ' || line[0] === '\t') {
			if (inBlock) {
				var m = line.match(/^\s+version\s+"([^"]+)"/);
				if (m) return m[1];
			}
			continue;
		}
		if (line[line.length - 1] === ':') {
			var keyPart = line.slice(0, -1).trim();
			var keys = keyPart.split(',').map(function (k) { return k.trim(); });
			inBlock = keys.indexOf(target) >= 0;
		} else {
			inBlock = false;
		}
	}
	return null;
}

// Whether a package already declares the vitest >= 1 coverage provider.
function hasCoverageProvider(pkg) {
	return !!((pkg.devDependencies || {})['@vitest/coverage-v8'] ||
		(pkg.dependencies || {})['@vitest/coverage-v8']);
}

// Exact version to request for a package's coverage provider. Resolved from the
// committed lockfile so it matches the installed vitest; falls back to the
// declared spec when it is already exact (e.g. "2.1.5").
function resolveProviderVersion(spec) {
	var version = getLockfileVitestVersion(spec);
	if (version) return version;
	return /^[^~^]/.test(String(spec)) ? String(spec) : null;
}

// Patch a single (non-chained) script segment that contains a test runner.
// This is the inner logic that appends coverage flags to one command.
function patchRunner(s, vitestMajor) {
	// Vitest runner
	if (s.indexOf('vitest') >= 0) {
		if (vitestMajor >= 1) {
			if (s.indexOf('--coverage') < 0) {
				s = s + ' --coverage';
			}
			if (s.indexOf('--coverage.reporter=lcov') < 0 && s.indexOf('--coverageReporters') < 0) {
				s = s + ' --coverage.reporter=lcov';
			}
			// --minWorkers must accompany --maxWorkers: vitest 2.x derives
			// minThreads from minWorkers (unset -> full CPU count), which
			// conflicts with a capped maxThreads in the forks pool.
			if (s.indexOf('--minWorkers') < 0) {
				s = s + ' --minWorkers=2';
			}
			return s + ' --maxWorkers=2';
		}
		// vitest 0.x: no --maxWorkers; bare --coverage collides with the dotted
		// --coverage.reporter flag in the 0.25 CAC parser. Use the dotted
		// --coverage.enabled form, and cap parallelism via VITEST_MAX_THREADS /
		// VITEST_MIN_THREADS env (--no-threads would break per-file isolation:
		// shared localStorage mocks leak across test files).
		s = s.replace(/--coverage(?!\.|\w)/g, '--coverage.enabled=true');
		if (s.indexOf('--coverage.enabled') < 0) {
			s = s + ' --coverage.enabled=true';
		}
		if (s.indexOf('--coverage.reporter=lcov') < 0 && s.indexOf('--coverageReporters') < 0) {
			s = s + ' --coverage.reporter=lcov';
		}
		if (s.indexOf('VITEST_MAX_THREADS') < 0) {
			s = 'VITEST_MAX_THREADS=2 VITEST_MIN_THREADS=2 ' + s;
		}
		return s;
	}

	// Jest runner (including craco test which wraps jest)
	if (s.indexOf('jest') >= 0 || s.indexOf('craco test') >= 0) {
		s = s.replace(/--no-coverage/g, '');
		if (s.indexOf('--coverage') < 0) {
			s = s + ' --coverage';
		}
		if (s.indexOf('--coverageReporters') < 0) {
			s = s + ' --coverageReporters=lcov';
		}
		return s + ' --maxWorkers=2';
	}

	return s;
}

// Rewrite any inline `--max_old_space_size=<n>` / `--max-old-space-size=<n>`
// (used both bare and inside NODE_OPTIONS="...") to the global HEAP_MB value.
function raiseHeap(s) {
	return s.replace(/--max[-_]old[-_]space[-_]size=\d+/g, '--max-old-space-size=' + HEAP_MB);
}

function patchScript(s, vitestMajor) {
	if (typeof s !== 'string' || s.trim() === '') return s;

	// Normalise any inline heap cap so it cannot override the global heap.
	s = raiseHeap(s);

	// E2E / storybook suites must never run as part of the root `test` dispatch.
	if (s.indexOf('cypress') >= 0 || s.indexOf('playwright') >= 0) {
		return 'node -e "console.log(\'[patch-coverage] skipping e2e suite\'); process.exit(0)"';
	}
	if (s.indexOf('test-storybook') >= 0) {
		return 'node -e "console.log(\'[patch-coverage] skipping storybook test suite\'); process.exit(0)"';
	}

	// test:compilation scripts (tsc --noEmit) — skip, they're typechecks
	if (s.indexOf('tsc') >= 0 && s.indexOf('--noEmit') >= 0) {
		return s;
	}

	// Handle chained scripts (containing &&) — only patch the segment that
	// contains the test runner, leaving build/typecheck segments untouched.
	// This prevents coverage flags from leaking onto `yarn test:compilation`
	// (which runs `tsc --noEmit`) when the script is e.g.
	//   jest ... && yarn test:compilation
	if (s.indexOf('&&') >= 0) {
		var parts = s.split('&&');
		var patchedParts = [];
		for (var i = 0; i < parts.length; i++) {
			var seg = parts[i];
			var hasRunner = (seg.indexOf('vitest') >= 0 || seg.indexOf('jest') >= 0 || seg.indexOf('craco test') >= 0);
			patchedParts.push(hasRunner ? patchRunner(seg, vitestMajor) : seg);
		}
		return patchedParts.join(' && ');
	}

	// Simple (non-chained) script — patch directly
	return patchRunner(s, vitestMajor);
}

function patchRoot(pkg) {
	var s = (pkg.scripts || {}).test || '';
	if (/lerna run test/.test(s)) {
		if (s.indexOf('--no-bail') < 0) {
			pkg.scripts.test = s + ' --no-bail --concurrency=1';
		}
	}
}

// Walk the whole repo (excluding install/build output) and collect every
// package.json, so no workspace is ever missed regardless of layout changes
// across the 2020-2025 timeframe.
var dirs = [];
var SKIP_DIRS = ['node_modules', '.git', 'dist', 'build', 'lib', '.nx', '.turbo'];
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
var providerNeeds = [];
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
		var vitestMajor = getVitestMajor(pkg);
		var vitestSpec = (pkg.devDependencies || {}).vitest || (pkg.dependencies || {}).vitest;
		Object.keys(scripts).forEach(function (name) {
			if (!isPatchableScriptName(name)) return;
			var def = scripts[name];
			if (typeof def !== 'string') return;
			var patched = patchScript(def, vitestMajor);
			if (patched !== def) {
				scripts[name] = patched;
				didPatch = true;
			}
		});
		// vitest >= 1 needs @vitest/coverage-v8 to be resolvable, but adding it
		// to package.json would force a non-frozen yarn install, which rewrites
		// yarn.lock and re-hoists the workspace (this is what introduced a
		// duplicate `vite` and broke packages/login's tsc). Record the need
		// instead; install-and-run.sh installs it out-of-tree after the frozen
		// install and symlinks it in.
		if (vitestMajor >= 1 && !hasCoverageProvider(pkg)) {
			var providerVersion = resolveProviderVersion(vitestSpec);
			if (providerVersion) {
				providerNeeds.push({
					name: '@vitest/coverage-v8',
					version: providerVersion,
					dir: dir
				});
			}
		}
	}

	if (didPatch) {
		writeJson(pkgFile, pkg);
		changed.push(dir);
	}
}

// Consumed by install-and-run.sh. Always written (even when empty) so a stale
// file from a previous checkout cannot leak in.
var providerFile = path.join(process.cwd(), '.coverage-providers.json');
fs.writeFileSync(providerFile, JSON.stringify({ providers: providerNeeds }, null, 2) + '\n');

console.log('Patched package.json files (' + changed.length + '): ' + changed.join(', '));
if (providerNeeds.length) {
	console.log('Coverage providers to install out-of-tree: ' + providerNeeds.map(function (p) {
		return p.name + '@' + p.version + ' (' + p.dir + ')';
	}).join(', '));
}