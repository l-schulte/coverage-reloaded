# polkadot-apps

> **Archived project (unstable).** Content extracted from the legacy single-file
> `projects/OVERVIEW.md` (2026-09-10) to preserve the information.

Root workspace with `jest` (short era) and `polkadot-dev-run-test`. Packages without
own scripts.

- `test`: runs `jest` and `polkadot-dev-run-test` with parameters, excluding "slow" tests.
- `test:all`: runs `polkadot-dev-run-test` with jest config for slow tests (require a running docker container)

We call both `test` and `test:all` when available and wrap them in c8.

## Config

```json
"polkadot-apps": {
    "url": "https://github.com/polkadot-js/apps",
    "node_version_overrides": [
        {
            "start_ts": 1628856104,
            "end_ts": 1657386674,
            "old_version": 12,
            "new_version": "14"
        }
    ]
}
```

## Checklist

- [x] 100 done (98/100)
- [ ] failed tests doublechecked
- [no] complete run

## Known Test Failures

- **node:test-era `jest.fn().mockClear has not been implemented`** (only in `test:all` / `unit_slow`, ~18 commits): the project's own `@polkadot/dev-test` jest-compat shim (the `jest` global on top of node:test) stubs `mockClear`, `mockReturnValue`, `mockResolvedValue`, `mockRejectedValue`, `mockReturnValueOnce`, `mockResolvedValueOnce`, `mockReturnThis`, `mockName`, `getMockName` to `throw new Error('… has not been implemented')` (via `stubObj` in `env/jest.js`). Specs that call e.g. `jest.fn().mockClear()` in a `beforeEach`/`afterEach` hook throw and the whole spec file fails to run, contributing ~0 coverage.
	* **Verified repo-intrinsic (faithful):** across the pinned `dev-test` versions at these commits (0.75.10 → 0.83.3) `env/jest.js` is byte-identical (same md5) and `mockClear` appears only in `MOCK_KEYS_STUB`, never as an implemented method. So the developers' own `yarn test:all` failed these specs too.
	* **Deliberately NOT polyfilled:** recovering them would inflate the exposure variable with coverage that never ran for the developers (a confound per AGENTS.md §1/§7), and any partial shim would be inconsistent (only `mockClear` covered, not `mockReturnValue` etc.). The resulting ~0 coverage for those specs is the faithful signal. Affects only `unit_slow`; the primary `unit` (`yarn test`) suite is clean.
- Runner-level `TypeError: Cannot read properties of undefined (reading 'error')` in `@polkadot/dev/scripts/polkadot-exec-node-test.mjs` `complete()` (2 commits) and an `Invalid key format` crypto/key spec failure (1 commit) — separate, genuine spec failures; exit 1 → valid partial coverage.
- `check configured chain endpoints` slow tests with multiple, separate, issues. Should have little effect on coverage though.
	* connect to real websocket urls on the internet (most of which do not exist)
	* raise TypeError: (0 , _xFetch.fetch)
- TypeError: Cannot read property 'proposeBounty' of undefined