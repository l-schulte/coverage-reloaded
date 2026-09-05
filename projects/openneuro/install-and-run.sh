#!/bin/bash
set -e
source /coverage_reloaded/logging.sh
source /coverage_reloaded/fake-time.sh
source /coverage_reloaded/resolve-and-pin.sh
cd /coverage_reloaded/repo

# libfaketime deadlocks Node's event loop because an absolute FAKETIME freezes
# the clock, so any code waiting on a realtime deadline busy-loops at 100% CPU
# (jest hangs forever). helper/fake-time.sh therefore uses a RELATIVE offset
# (commit date but clock keeps advancing); these exports are kept as belt-and-
# braces so CLOCK_MONOTONIC stays real and getpid() isn't faked.
export FAKETIME_DONT_FAKE_MONOTONIC=1
export FAKETIME_DONT_FAKE_PID=1

export ELASTICSEARCH_CONNECTION="${ELASTICSEARCH_CONNECTION:-http://localhost:9200}"
export JWT_SECRET="${JWT_SECRET:-openneuro-test-secret}"

if [ ! -f package.json ]; then
  print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
  exit 2
fi

# Set javascript heap size to 8GB.
export NODE_OPTIONS="--max_old_space_size=8192"

# ── Install ────────────────────────────────────────────────
# mongodb-memory-server downloads its server binary from fastdl.mongodb.org
# during install postinstall; that host intermittently fails first-try DNS
# resolution (EAI_AGAIN). Pin it up front (retries with backoff) so the
# download is stable.
resolve_and_pin "fastdl.mongodb.org"
resolve_and_pin "downloads.sentry-cdn.com"
resolve_and_pin "codeload.github.com"

print_header 2 "Installing dependencies"
# Allow mutable installs so we can add a missing @vitest/coverage-* provider
# when the checked-out commit lacks one.
export YARN_ENABLE_IMMUTABLE_INSTALLS=false

YARN_VER=$(yarn --version 2>/dev/null || echo "0")
for f in $(find packages services -name package.json 2>/dev/null); do
  sed -i -E 's#("bids-validator": *)"file:[^"]*"#\1"1.6.2"#' "$f"
done
if [ -f yarn.lock ]; then
  sed -i '/^"bids-validator@file:bids-validator":$/,/^$/d' yarn.lock
fi
if [ "$IS_YARN_MAIN_PM" = "true" ]; then
  yarn install

  set +e
  yarn build
  BUILD_EXIT=$?
  set -e
  if [ "$BUILD_EXIT" -gt 0 ]; then
    echo "[WARN] yarn build (tsc -b) reported type errors (exit $BUILD_EXIT) — continuing; tests resolve emitted dist"
  fi
else
  print_header 2 "Unexpected package manager, expected yarn"
  exit 1
fi

# ── Detect runner from the checked-out commit ──────────────
TEST_SCRIPT=$(node -p "require('./package.json').scripts.test || ''")
HAS_V8=$(node -p "!!(require('./package.json').devDependencies||{})['@vitest/coverage-v8']")
HAS_C8P=$(node -p "!!(require('./package.json').devDependencies||{})['@vitest/coverage-c8']")

# vitest 0.x minor version drives the coverage-provider choice: v8 became the
# default (and c8 was deprecated) in vitest 0.32 (PR #3339), so >=0.32 needs
# @vitest/coverage-v8 and <0.32 needs @vitest/coverage-c8. The major is always
# 0 for the 0.x line, so gate on minor, not major.
VMAJOR=$(node -p "parseInt((require('./package.json').devDependencies['vitest']||'0').replace(/[^0-9.]/g,'').split('.')[0]||'0')")
VMINOR=$(node -p "parseInt((require('./package.json').devDependencies['vitest']||'0').replace(/[^0-9.]/g,'').split('.')[1]||'0')")
VITEST_VER=$(node -p "require('./package.json').devDependencies['vitest']||'0'")
NEEDS_V8=false
if [ "${VMAJOR:-0}" -ge 1 ] 2>/dev/null; then
  NEEDS_V8=true
elif [ "${VMINOR:-0}" -ge 32 ] 2>/dev/null; then
  NEEDS_V8=true
fi

if echo "$TEST_SCRIPT" | grep -q vitest; then
  # ── Vitest era ───────────────────────────────────────────
  # Coverage provider often missing from devDependencies; install the
  # era-appropriate one via WayPack so `--coverage` produces lcov. Gate on the
  # vitest MINOR (>=0.32 ⇒ v8), not on whether c8 happens to be declared — a
  # checked-out commit can ship @vitest/coverage-c8 yet run vitest 0.33, which
  # refuses c8 and errors with "MISSING DEP @vitest/coverage-v8".
  if [ "$NEEDS_V8" = "true" ]; then
    if [ "$HAS_V8" != "true" ]; then
      print_header 4 "vitest >=0.32 but @vitest/coverage-v8 missing — installing v8 provider via WayPack"
      yarn add -D "@vitest/coverage-v8@$VITEST_VER"
    fi
  else
    if [ "$HAS_C8P" != "true" ]; then
      print_header 4 "vitest <0.32 but @vitest/coverage-c8 missing — installing c8 provider via WayPack"
      yarn add -D "@vitest/coverage-c8@$VITEST_VER"
    fi
  fi

  # Coverage via vitest dot-notation flags (`--coverage.enabled` +
  # `--coverage.reporter=lcov`), which work across openneuro's vitest range and
  # avoid cac's boolean-dot-notation guard. `fake_time` pins the wall clock so
  # date snapshots pass; FAKETIME_DONT_FAKE_MONOTONIC (above) stops libfaketime
  # from deadlocking Node's event loop on exit. `--coverage.reportOnFailure`
  # (gated to vitest >= 0.32; 0.25.2 lacks it) emits the lcov even on test
  # failure instead of skipping the report on a non-zero exit.
  VKEY=$(node -p "(function(){var v=(require('./package.json').devDependencies['vitest']||'0');var m=v.match(/[0-9]+/g);if(!m||!m[1])return 0;return (+m[0])*100+(+m[1]);})()")
  REPORT_ON_FAIL=""
  if [ "${VKEY:-0}" -ge 32 ] 2>/dev/null; then
    REPORT_ON_FAIL="--coverage.reportOnFailure"
  fi

  suite_start "vitest" "Running vitest with coverage (vitest era)"
  set +e
  fake_time yarn vitest run --coverage.enabled --coverage.reporter=lcov $REPORT_ON_FAIL
  VITEST_EXIT=$?
  set -e
  bash /coverage_reloaded/find-and-move-lcov.sh "vitest" "true" "$VITEST_EXIT"
  suite_end "vitest" "$VITEST_EXIT"
else
  # ── Jest era ─────────────────────────────────────────────
  # The root jest config uses `projects: ["packages/*"]`, so `jest --coverage`
  # collects coverage for every package and writes one lcov.info per package.
  set +e
  # Yarn berry (PnP) can't resolve binaries through `yarn exec --` (no .bin
  # symlinks) -> "spawn jest ENOENT". Use `yarn jest`, which goes through PnP
  # bin lookup. Yarn classic instead swallows `yarn jest --coverage` (treats
  # --coverage as its own flag), so classic keeps `yarn exec -- jest`.
  YARN_MAJOR=$(yarn --version 2>/dev/null | cut -d. -f1)
  if [ "${YARN_MAJOR:-1}" -ge 2 ] || [ -f .yarnrc.yml ]; then
    suite_start "jest_berry" "Running jest with coverage (jest era)"
    fake_time yarn jest --coverage --coverageReporters=lcov --maxWorkers=2 --forceExit
    JEST_BERRY_EXIT=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "jest_berry" "true" "$JEST_BERRY_EXIT"
    suite_end "jest_berry" "$JEST_BERRY_EXIT"
  else
    suite_start "jest" "Running jest with coverage (jest era)"
    fake_time yarn exec -- jest --coverage --coverageReporters=lcov --maxWorkers=2 --forceExit
    JEST_EXIT=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "jest" "true" "$JEST_EXIT"
    suite_end "jest" "$JEST_EXIT"
  fi
fi

print_header 1 "OpenNeuro coverage run complete"
