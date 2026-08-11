# Polkadot-Apps — Test Failure Report

**Scope:** current `logs/` and `output/` folders only (older `logs_1..5` / `output_1..6`
ignored, and the `*_2026…_…` debug reruns treated as duplicates of their canonical
`.log`).

## Corpus

100 canonical runs: 97 `.log` + 3 `.error`, plus 3 `.not_applicable` (early
"skipping tests" commits). Two suites per commit:

- `unit` — fast suite (`yarn test`)
- `unit_slow` — `yarn test:all`, which spins up a parity/substrate container via testcontainers

Exit codes are stored in `<suite>.exit_code` sidecars. Per AGENTS.md §7, exit `0/1`
= coverage-valid (warning); hard error / no-lcov = failure.

| Suite | exit 0 | exit 1 | hard error / no coverage |
|---|---|---|---|
| `unit` | 90 (+2 `unit_polkadot`) | 2 | 3 |
| `unit_slow` (`test:all`) | 14 | 67 | — |

The dominant signal: the fast `unit` suite is almost always green; `test:all` fails on
~83% of commits where it exists, but almost always with exit code 1 and **valid
coverage still produced**.

---

## Failure groups

### Group 1 — `test:all` / `unit_slow` behavioral failures (exit 1, coverage produced)
**~67 commits. Dominant group. PRE-EXISTING / EXPECTED — left as-is.**

Runs finish, write `unit_slow.lcov`, and exit 1 because a subset of specs fail. The
failing specs change over history but cluster into recurring, environment-rooted causes:

- **Slow UI tests time out (jest era, 2020–2022):** `CreateAccount.spec.tsx`,
  `CreateAccount.slow.spec.tsx`, `Bounties.slow.spec.tsx` — React Testing Library
  `findBy…` timeouts.
- **`node:test` era (2023+):** recurring trio —
  - `apps-config/.../typesBundle*.spec.ts` → `undefined / undefined` (type-bundle/network checks)
  - `apps-electron/.../account-store.spec.ts` → `Error: Invalid key format` (ui-keyring FileStore)
  - `apps-electron/.../remote-electron-store.spec.ts` → `Error: jest.fn().mockClear has not been implemented` (limitation in the project's own `@polkadot/dev-test` jest shim)

**Assessment:** genuine, pre-existing behavioral/environmental failures; coverage still
valid and dominated by the passing majority. The two clearly non-behavioral specs
(`chainEndpoints`, `CreateAccount.slow`) are already excluded in `install-and-run.sh`.
No fix required for validity.

### Group 2 — `.cjs` module-resolution collapse in `test:all`
**6 commits, 2021-07-14 → 2021-08-26** (`1626276306`, `1628328173`, `1629436185`,
`1629454004`, `1629579924`, `1629974999`). **NEEDS A TARGETED FIX.**

`test:all` mass-fails to load ~14 suites with `Cannot find module './Backend.cjs'`
(and `./util.cjs`, `./stringHelpers.cjs`, `./account-store.cjs`, …), collapsing the
slow suite to ~2 executed tests. The fast `unit` suite at these commits passes and
produces full coverage, so the merged artifact is still reasonable but `unit_slow` is
degraded.

**Corrected root cause (from investigation):** NOT a missing build step.
`@polkadot/dev`'s babel plugin `babel-plugin-module-extension-resolver` rewrites
relative imports `./foo` → `./foo.cjs`. In
`node_modules/@polkadot/dev/config/babel-plugins.cjs` this is gated:

```js
const rewriteExt = !process.env.JEST_WORKER_ID && withExt && (isEsm || EXT_CJS !== '.js');
```

The plugin is meant to be disabled under Jest, but only when `JEST_WORKER_ID` is set.
When it is unset, jest wrongly resolves `./foo` → `./foo.cjs` and the sibling `.ts`
cannot be found. Single-spec runs pass (worker id present); the failure surfaces with
our full `--runInBand --coverage` multi-spec `test:all` invocation.

**`build:code` is the wrong fix.** It compiles into each package's `build/` dir (not
next to `src`), so the wanted `.cjs` siblings are still absent, and it *regressed* a
previously-working commit (`1621070979`: `unit_slow` dropped from 71 passing tests to
2). It was tried and reverted.

**Likely fix (to verify in-container):** force `JEST_WORKER_ID` around the `test:all`
invocation, or adjust runner flags for the `jest-slow.config.cjs` era, so the babel
plugin does not rewrite extensions.

### Group 3 — `usb-detection` native bindings missing
**1 commit** (`1636119047`, 2021-11-05) — fast `unit` exits 1. **ENVIRONMENTAL / native-build.**

7 suites fail to load with `Could not locate the bindings file …
usb-detection/build/Release/detection.node` (chain: `@polkadot/ui-keyring` →
`hw-ledger` → `hw-transport-node-hid-singleton` → `usb-detection`). The native module
wasn't compiled in the image. Low priority (10 other suites still produced coverage).

### Group 4 — Electron binary not installed (`apps-electron`)
**Recurring in `test:all`; explicit in `1629974999`'s fast suite.** **ENVIRONMENTAL.**

`apps-electron/.../account-store.spec.ts` → `Electron failed to install correctly,
please delete node_modules/electron and try installing again`. Contributes to Group
1/2 failures. Coverage still produced. Low priority.

### Group 5 — `c8` install fails: `node: Permission denied`
**2 HARD errors** (`1594284375`, `1594416350`, 2020-07). **SHOULD FIX — our own tooling.**
Produced `output/*.error`, **no coverage**.

`npx --registry=$VERDACCIO_REGISTRY c8` install aborts because the `core-js-pure@3.6.5`
postinstall runs `node …` and hits `sh: 1: node: Permission denied` →
`Install for c8@latest failed with code 1` → `No lcov.info files found`. A
coverage-tooling / environment bug in our harness, not a project test failure.

### Group 6 — corepack cannot fetch `yarn@4.1.0`
**1 HARD error** (`1711070427`, 2024-03). **TRANSIENT / INFRA — retry.**
Produced `output/*.error`, no coverage.

Fails in `execute.sh` setup (before `install-and-run.sh`): `corepack … Error when
performing the request to https://repo.yarnpkg.com/4.1.0/…/yarn.js`. Network/corepack
fetch failure.

---

## Summary table

| Group | Commits | Exit signal | Coverage? | Verdict |
|---|---|---|---|---|
| 1. `test:all` behavioral failures | ~67 | 1 (soft) | Yes (valid) | Pre-existing/expected — no fix |
| 2. `.cjs` resolution collapse | 6 (Jul–Aug '21) | 1 (soft) | Partial (slow suite degraded) | Needs targeted fix (babel `JEST_WORKER_ID`/`.cjs` gate) |
| 3. `usb-detection` bindings | 1 (`1636119047`) | 1 (fast suite) | Yes (partial) | Environmental — low priority |
| 4. Electron not installed | recurring | 1 (soft) | Yes | Environmental — low priority |
| 5. `c8` install `node: Permission denied` | 2 (2020-07) | hard error | None | Our tooling bug — should fix |
| 6. corepack yarn@4.1.0 fetch | 1 (2024-03) | hard error | None | Transient/infra — retry |

## Net

- **Pre-existing / expected, no action:** Group 1 (67); Groups 3 & 4 (coverage still produced).
- **Genuine harness issues worth fixing:** Group 5 (2 commits, zero coverage), Group 6
  (1 commit, retry), and Group 2 (6 commits — real cause now understood: the babel
  `JEST_WORKER_ID` / `.cjs` gate, not a missing build).
