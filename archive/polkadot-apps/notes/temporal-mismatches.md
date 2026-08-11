# Polkadot Apps — Temporal API Mismatches

## testcontainers: `withCmd` → `withCommand`
- `withCmd()` existed in testcontainers v1.1.18 through v8.16.0
- Renamed to `withCommand()` in v8.17.0 (breaking change)
- Project's `yarn.lock` pins `^9.1.1` which is past the boundary
- Fix: `yarn up testcontainers@8.16.0` after install

## Substrate CLI flags: `--ws-port` → `--rpc-port`
- Substrate 2.0.0 used `--ws-port=9944` / `--unsafe-ws-external`
- Substrate 3.0.0-dev renamed to `--rpc-port=9944` / `--unsafe-rpc-external`
- Project's `globalSetup.cjs` uses the old 2.0.0 flag names
- Lookup CSV maps to 3.0.0-dev tags for commits after mid-2021
- Fix: `sed` patch in install-and-run.sh when pulling 3.0.0-dev images

## AlwaysPullPolicy
- `AlwaysPullPolicy` class existed in testcontainers ≤8.16.0
- Removed in v8.17.0+ (use `PullPolicy.alwaysPull()` instead)
- Fixed by downgrading to 8.16.0 (same `yarn up` fix as above)
