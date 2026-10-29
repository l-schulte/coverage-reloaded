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

// Cap vitest's worker pool. Inside the container Node sees the HOST's core
// count (os.cpus()/availableParallelism → nproc = 256) while the cgroup CPU
// quota is only a few cores; docker-run.sh caps the CPU *quota*, not the core
// count Node sees. Without a cap vitest sizes its pool from that 256
// (maxThreads = cpus().length - 1), and hundreds of workers thrash the few real
// cores, so tests blow their 5s/10s timeouts — the dominant n8n failure mode.
// Same rationale as jest's --maxWorkers=1 below; the pool must be capped here.
// Flag availability is version-dependent:
//   vitest >= 1.0 -> --maxWorkers=<n>
//   vitest < 1.0  -> bounded via VITEST_MAX_THREADS env vars in install-and-run.sh
//                    (--single-thread / --no-threads break worker isolation and hang)
var VITEST_WORKERS = 2;

function vitestVersion(dir, pkg) {
	// Prefer the installed version (exact); fall back to the declared spec.
	try {
		var p = require.resolve('vitest/package.json', { paths: [path.resolve(dir)] });
		var v = readJson(p).version;
		if (v) return v;
	} catch (e) { /* not installed / not resolvable */ }
	var spec = (pkg && pkg.devDependencies && pkg.devDependencies.vitest) ||
		(pkg && pkg.dependencies && pkg.dependencies.vitest) || '';
	var m = String(spec).match(/(\d+\.\d+)/);
	return m ? m[1] : '';
}

function vitestCap(dir, pkg) {
	var m = vitestVersion(dir, pkg).match(/^(\d+)\.(\d+)/);
	if (!m) return ''; // unknown version -> never risk an unsupported flag
	var major = parseInt(m[1], 10);
	if (major >= 1) return ' --maxWorkers=' + VITEST_WORKERS;
	// For vitest < 1.0 (0.x), do NOT pass --single-thread or --no-threads:
	// running without worker thread isolation causes packages/editor-ui (jsdom)
	// to hang indefinitely on open event loop handles.
	// Instead, the pool is safely bounded via VITEST_MAX_THREADS in install-and-run.sh
	// while keeping worker threads enabled.
	return '';
}

function patchScript(s, dir, pkg) {
	if (typeof s !== 'string' || s.trim() === '') return s;
	if (s.indexOf('playwright') >= 0) {
		// E2E suite must never run as part of the root `test` dispatch.
		return 'node -e "console.log(\'[patch-coverage] skipping playwright e2e suite\'); process.exit(0)"';
	}
	if (s.indexOf('Error: no test specified') >= 0) {
		// Placeholder script in scaffolded packages (e.g. @n8n/n8n-benchmark)
		return 'node -e "console.log(\'[patch-coverage] skipping placeholder test\'); process.exit(0)"';
	}
	if (s.indexOf('jest') >= 0) {
		s = s.replace(/--no-coverage/g, '');
		// --maxWorkers=1: n8n's test suites are NOT safe to parallelise across
		// workers — the cli integration tests migrate the same `database.sqlite`
		// file from every worker (concurrent migrations → 10s hook timeouts and
		// partial schemas), and nodes-base workflow tests share global nock /
		// @n8n/di state that corrupts interceptor matching under >1 worker.
		// --testTimeout=30000: integration tests in packages/cli (e.g. reset.cmd.test.ts)
		// take ~5-7.5s under coverage instrumentation and exceed Jest's default 5000ms limit.
		return s + ' --coverage --coverageReporters=lcov --maxWorkers=1 --testTimeout=30000';
	}
	if (s.indexOf('vitest') >= 0) {
		s = s.replace(/\s+reporters=lcov/g, '');
		s = s.replace(/--coverage\.enabled/g, '');
		s = s.replace(/--coverage\.reporter=\S+/g, '');
		s = s.replace(/--coverage/g, '');
		return s.trim().replace(/\s+/g, ' ') +
			' --coverage.enabled --coverage.reporter=lcov' + vitestCap(dir, pkg);
	}
	if (s.indexOf('vue-cli-service') >= 0) {
		return s + ' --coverage --coverageReporters=lcov';
	}
	return s;
}

function patchRoot(pkg) {
	var s = (pkg.scripts || {}).test || '';
	if (/lerna run test/.test(s)) {
		if (s.indexOf('--no-bail') < 0) pkg.scripts.test = s + ' --no-bail --concurrency=1 --stream';
		else if (s.indexOf('--stream') < 0) pkg.scripts.test = s + ' --stream';
	} else if (/turbo run test/.test(s)) {
		if (s.indexOf('--continue') < 0) {
			pkg.scripts.test = s.replace(/turbo run test/, 'turbo run test --continue --concurrency=1');
		}
	}

	// Build ordering (lerna era, 2021-01..2022-08). The legacy root build is a
	// PARALLEL, unordered `lerna exec npm run build`, so a package can compile
	// against a dependency whose dist/ has not been rebuilt yet:
	//   error TS2305: Module '.../n8n-workflow/dist/src' has no exported member X
	//   Error: Failed to resolve entry for package "n8n-workflow"
	// `lerna run build` is topologically sorted, so dependencies build first.
	// Only the exact legacy script is rewritten; the turbo era already declares
	// dependsOn ["^build"] and is left untouched.
	var b = (pkg.scripts || {}).build || '';
	if (/^lerna exec npm run build\s*$/.test(b)) {
		pkg.scripts.build = 'lerna run build';
	}
}

// Remove `include: ['src/**/*.ts']` from vite/vitest configs in frontend packages.
// Upstream originally restricted coverage to TypeScript files in commit eb3ba83e63 (2023-03-14),
// preventing c8 from collecting coverage on .vue files even though component unit tests were
// being added. Upstream corrected this on 2023-05-11 in commit 82687902f8 ("ci: Code coverage
// should include `.vue` files as well"). Backporting this fix unlocks real Vue coverage for
// the March-May 2023 window.
function patchViteConfig(dir) {
	var candidates = ['vite.config.ts', 'vite.config.js', 'vitest.config.ts', 'vitest.config.js'];
	for (var i = 0; i < candidates.length; i++) {
		var filePath = path.join(dir, candidates[i]);
		if (!fs.existsSync(filePath)) continue;
		try {
			var content = fs.readFileSync(filePath, 'utf8');
			var patched = content.replace(/[ \t]*include:\s*\[\s*['"]src\/\*\*\/\*\.ts['"]\s*\],?\r?\n?/g, '');
			if (patched !== content) {
				fs.writeFileSync(filePath, patched, 'utf8');
				console.log('[patch-coverage] Removed TypeScript-only coverage restriction from ' + filePath);
			}
		} catch (e) { /* ignore */ }
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
	patchViteConfig(dir);
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
		if (pkg.name === 'n8n-node-dev' && scripts.build) {
			// Auxiliary developer CLI tool with no tests and no dependents in the repo.
			// Its dependencies drifted for 6-month stretches upstream, breaking tsc.
			scripts.build = 'node -e "process.exit(0)"';
			didPatch = true;
		}
		var hasVueCli = false;
		Object.keys(scripts).forEach(function (name) {
			if (!isPatchableScriptName(name)) return;
			var def = scripts[name];
			if (typeof def !== 'string') return;
			if (def.indexOf('vue-cli-service') >= 0) hasVueCli = true;
			var patched = patchScript(def, dir, pkg);
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
