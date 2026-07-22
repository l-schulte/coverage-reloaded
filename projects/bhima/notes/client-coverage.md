# bhima — Client Coverage

## Status: Collectable via karma-coverage + babel

Client-unit tests (Karma + AngularJS 1.x) produce source-level lcov coverage
using a sidecar Karma config with karma-coverage and babel transpilation.

## Approach

The gulp pipeline (`gulp-concat → gulp-typescript outFile → gulp-iife`) cannot
produce per-file source maps — `outFile` mode collapses all sources into one
before tsc sees them, so the source map only references the concat intermediate,
not individual source files. Remap-based approaches were explored and abandoned.

Instead: individual source files are loaded directly into Karma (replicating the
`CLIENT_JS` glob from `gulpfile.js/client-js.js`), replacing the compiled bundle
in the files array. `karma-coverage` instruments each file, `karma-babel-preprocessor`
transpiles to ES5 first — required because raw ES6+ arrow functions break AngularJS's
DI injector (`Function.prototype.bind.apply(...) is not a constructor`).

## Tools

Installed in `/coverage_reloaded/harness/`, symlinked into project `node_modules/`
after WayPack install:

- `karma-coverage`
- `@babel/core@7.22.0` — pinned to 7.x; v8 is ESM-only, incompatible with karma-babel-preprocessor
- `@babel/preset-env@7.22.0`
- `karma-babel-preprocessor`

## Sidecar config

`/coverage_reloaded/harness/karma.sidecar.conf.js` — layers on top of committed
`karma.conf.js` without modifying it. Key overrides:

- Replaces `bin/client/js/bhima/bhima.min.js` with individual source files
- Preprocessor globs: `client/src/js/**/*.js`, `client/src/modules/**/*.js`,
  `client/src/components/**/*.js` — excludes `client/src/i18n/` matching `CLIENT_JS`
- `singleRun: true`, `client.mocha.bail: false`
- `ChromeHeadlessNoSandbox` custom launcher (required — container runs as root)

`/coverage_reloaded/harness/babel.config.json` — targets `ie: 11` (ES5), matching
the project's own `tsconfig` target.

## Output

- ~735 source files, relative paths (`client/src/...`)
- ~3133 hit lines on a clean run
- 227 of 248 tests pass (21 skipped) — matches baseline without instrumentation
- lcov written to `/coverage_reloaded/harness/output/lcov.info`, copied to
  `coverage/client/lcov.info`, then moved by `find-and-move-lcov.sh`

## Karma config history

23 commits touch `karma.conf.js`. Two distinct shapes:
- `ChromeHeadless` (from `2869ecace`, March 2019 onwards) — entire 5-year study window
- `Chrome` (before March 2019) — outside study window, not relevant

Sidecar hardcodes `ChromeHeadlessNoSandbox` — safe for all commits in scope.

## Failure guards in install-and-run.sh

1. `bhima.min.js` must exist — confirms build ran (vendor assets still needed)
2. `lcov.info` must be produced — confirms karma-coverage fired
3. No `Function.prototype.bind.apply.*is not a constructor` in karma output —
   detects babel failure silently corrupting coverage data
4. At least one non-zero DA entry — confirms instrumentation reached test execution

## Key decisions and dead ends

| Attempt | Why abandoned |
|---|---|
| Source maps via gulpfile patch | `outFile` emits one source ref (concat intermediate), remap resolves to `bhima.concat.js` not source files |
| `remap-istanbul` | Throws on null line numbers in branch mappings from `outFile` source maps |
| `istanbul-lib-source-maps` | Remaps to `bhima.min.js` (bundle), not sources — same root cause |
| Raw source files without babel | ES6 arrows break AngularJS DI injector |
| `@babel/core@8` | ESM-only, incompatible with `karma-babel-preprocessor` require() |
| Broad preprocessor glob | Instrumented i18n locale files; tightened to match `CLIENT_JS` |