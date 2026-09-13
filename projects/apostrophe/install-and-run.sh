#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

REPOPATH="${REPOPATH:-/coverage_reloaded/repo}"
export REPOPATH
COVERAGE_REPORT_PATH="${COVERAGE_REPORT_PATH:-/coverage_reloaded/exported}"
export COVERAGE_REPORT_PATH
mkdir -p "$COVERAGE_REPORT_PATH"

cd "$REPOPATH"

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit"
    exit 2
fi

# The i18n hostname tests fetch http://<locale>.localhost:<port>/. Bullseye's
# glibc 2.31 resolves *.localhost only to ::1, and execute.sh disables IPv6, so
# those lookups fail with getaddrinfo ENOTFOUND unless the IPv4 loopback is
# pinned explicitly (the project's Ubuntu CI has glibc >= 2.35 and resolves it).
for host in ca.localhost en.localhost; do
    if ! grep -q " $host\$" /etc/hosts 2>/dev/null; then
        echo "127.0.0.1 $host" >> /etc/hosts
    fi
done
print_header 4 "Pinned locale hostnames" "ca.localhost, en.localhost -> 127.0.0.1"

# ── MongoDB engine selection ──────────────────────────────────
# Apostrophe used the mongodb 3.x driver until 2024-04-04, which cannot talk to
# MongoDB 5.0+. From that commit on it uses @apostrophecms/emulate-mongo-3-driver
# on driver 6.x. Detect the driver from the checked-out commit rather than from
# the date, then start the matching engine (4.4 or 7.0).
HAS_EMULATE=0
if node -e '
  const fs = require("fs");
  for (const f of [ "package.json", "packages/apostrophe/package.json" ]) {
    try {
      const p = JSON.parse(fs.readFileSync(f, "utf8"));
      const deps = Object.assign({}, p.dependencies, p.devDependencies);
      if (deps["@apostrophecms/emulate-mongo-3-driver"]) process.exit(0);
    } catch (e) {}
  }
  process.exit(1);
'; then
    HAS_EMULATE=1
fi

if [ "$HAS_EMULATE" = "1" ]; then
    MONGOD_BIN=/usr/local/bin/mongod-7.0
    MONGO_ENGINE="7.0"
else
    MONGOD_BIN=/usr/local/bin/mongod-4.4
    MONGO_ENGINE="4.4"
fi

print_header 3 "Starting MongoDB $MONGO_ENGINE"
rm -rf /tmp/mongodb
mkdir -p /tmp/mongodb
"$MONGOD_BIN" --dbpath /tmp/mongodb --logpath /tmp/mongodb/mongod.log --fork --bind_ip 127.0.0.1 --port 27017
print_header 4 "MongoDB $MONGO_ENGINE running ($MONGOD_BIN)"

# ── Dependency install ────────────────────────────────────────
print_header 2 "Installing dependencies"

if [ "${IS_PNPM_MAIN_PM:-false}" = "true" ]; then
    # The 2025-12-01 monorepo switch declared the private Pro module
    # @apostrophecms-pro/automatic-translation as a devDependency of
    # packages/import-export, which pnpm resolves over git+ssh. The container
    # has no ssh client and no credentials, and the repo is private. Upstream
    # made Pro testing optional on 2026-01-02 (TEST_WITH_PRO); mirror that by
    # dropping the dependency unless TEST_WITH_PRO is set. Only the
    # packages/apostrophe suites are run, so import-export never needs it.
    if [ -z "${TEST_WITH_PRO:-}" ]; then
        print_header 4 "Dropping private Pro devDependency (TEST_WITH_PRO unset)"
        node -e '
          const fs = require("fs");
          const key = "@apostrophecms-pro/automatic-translation";
          const fields = [ "dependencies", "devDependencies", "optionalDependencies", "peerDependencies" ];
          for (const file of [ "packages/import-export/package.json", "packages/import-export/test/package.json" ]) {
            if (!fs.existsSync(file)) continue;
            const pkg = JSON.parse(fs.readFileSync(file, "utf8"));
            let changed = false;
            for (const field of fields) {
              if (pkg[field] && Object.prototype.hasOwnProperty.call(pkg[field], key)) {
                delete pkg[field][key];
                changed = true;
              }
            }
            if (changed) {
              fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + "\n");
              console.log("Removed " + key + " from " + file);
            }
          }
        '
    fi
    # CI=true makes pnpm default to --frozen-lockfile, but apostrophe
    # gitignores its lockfiles, so there is nothing to freeze against.
    pnpm install --no-frozen-lockfile
elif [ "${IS_YARN_MAIN_PM:-false}" = "true" ]; then
    yarn install
elif [ "${IS_NPM_MAIN_PM:-false}" = "true" ]; then
    # From 2024-05-28 to 2024-06-12 package.json pinned stylelint-config-apostrophe
    # to an unpinned github: spec. npm clones the repo's default-branch HEAD at
    # install time, whose dependency set is newer than this commit's timestamp, so
    # WayPack (timestamp-scoped) cannot resolve it (ENOVERSIONS on
    # @apostrophecms/stylelint-no-mixed-decls, first published 2025-05-23). The
    # config is lint-only -- the collected test chain never runs stylelint -- so
    # drop it before install.
    node -e '
      const fs = require("fs");
      const key = "stylelint-config-apostrophe";
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      const spec = pkg.devDependencies && pkg.devDependencies[key];
      if (spec && /^(github:|git\+)/.test(spec)) {
        delete pkg.devDependencies[key];
        fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
        console.log("Removed " + key + " (" + spec + ") from package.json");
      }
    '
    npm install
else
    print_header 4 "ERROR: no supported main package manager detected"
    exit 1
fi

# nyc spawns the test runner by name, so the project's own binaries must be on
# PATH. npm and pnpm both link the root package's devDependencies here.
export PATH="$REPOPATH/node_modules/.bin:$PATH"

# mocha_check_passing
# Adopted from projects/flowfuse/install-and-run.sh. Reads a mocha run's output
# from stdin, streams it through live (so it still reaches the run log), and
# checks for an "N passing" summary. On an incomplete run (heap OOM, a
# suite-aborting error, or a `.only` rejected by --forbid-only) it discards any
# partial lcov.info so find-and-move-lcov.sh fails hard instead of recording
# misleading near-empty coverage as valid.
#   $test_command 2>&1 | mocha_check_passing
mocha_check_passing() {
    local out_file
    out_file=$(mktemp)
    tee "$out_file"
    if ! grep -qE '^[[:space:]]*[0-9]+ passing' "$out_file" 2>/dev/null; then
        print_header 4 "WARNING: mocha run did not complete (no passing-summary) — discarding partial coverage and failing hard"
        find "$REPOPATH" -name lcov.info -not -path '*/node_modules/*' -delete
        rm -f "$out_file"
        return 1
    fi
    rm -f "$out_file"
    return 0
}

# run_test_suite <label> <test_command> <prepend_paths>
run_test_suite() {
    local label="$1"
    local test_command="$2"
    local prepend="$3"
    local test_exit=0

    # uploadfs's local backend disables archived attachments by chmod'ing them
    # to 0000 (it only renames when disabledFileKey is set, which apostrophe
    # does not set). Our container runs as root, and CAP_DAC_OVERRIDE lets root
    # ignore those permission bits, so the "should not have been accessible"
    # tests would still read the file. Dropping the DAC capabilities mirrors the
    # project's non-root CI user without changing ownership.
    local run_prefix="setpriv --bounding-set=-dac_override,-dac_read_search --"

    print_header 4 "Test command: $run_prefix $test_command"
    suite_start "$label" "$test_command"

    set +e
    $run_prefix $test_command 2>&1 | mocha_check_passing
    test_exit="${PIPESTATUS[0]}"
    set -e

    bash ../find-and-move-lcov.sh "$label" "$prepend" "$test_exit"
    suite_end "$label" "$test_exit"
}

if [ -f pnpm-workspace.yaml ]; then
    # ── Monorepo era (from the 2025-12-01 monorepo switch) ────
    print_header 2 "Monorepo detected — running packages/apostrophe suites"

    if [ ! -f packages/apostrophe/package.json ]; then
        print_header 2 "NOT APPLICABLE" "No packages/apostrophe/package.json at this commit"
        exit 2
    fi

    run_pnpm_nyc_suite() {
        local script="$1"
        local label="$2"
        local def
        def=$(node -p "const p=require('./packages/apostrophe/package.json').scripts||{}; p['$script']||''")
        if [ -z "$def" ]; then
            print_header 4 "Script not present at this commit — skipping" "packages/apostrophe#$script"
            return 0
        fi
        case "$def" in
            nyc\ *) ;;
            *)
                print_header 4 "Script does not use nyc — skipping" "packages/apostrophe#$script: $def"
                return 0
                ;;
        esac
        local rest="${def#nyc }"
        rest="${rest/mocha/mocha --forbid-only --no-bail}"

        run_test_suite "$label" "pnpm --filter apostrophe exec nyc --reporter=lcov --reporter=text $rest" "true"
    }

    run_pnpm_nyc_suite "test:base" "base"
    run_pnpm_nyc_suite "test:missing" "missing"
    run_pnpm_nyc_suite "test:assets" "assets"
else
    # ── Single-package era (up to 2025-11-30) ─────────────────
    print_header 2 "Single package detected — running root mocha suites"

    TEST_DEF=$(node -p "require('./package.json').scripts.test || ''")
    if [ -z "$TEST_DEF" ]; then
        print_header 2 "NOT APPLICABLE" "No test script at this commit"
        exit 2
    fi

    HAS_SPLIT=0
    if printf '%s' "$TEST_DEF" | grep -q 'ignore=test/assets.js'; then
        HAS_SPLIT=1
    fi

    while IFS= read -r raw; do
        command="$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -z "$command" ] && continue
        case "$command" in
            nyc\ *) ;;
            *)
                print_header 4 "Skipping non-coverage command" "$command"
                continue
                ;;
        esac

        if printf '%s' "$command" | grep -q 'add-missing-schema-fields-project'; then
            label="missing"
        elif printf '%s' "$command" | grep -q 'ignore=test/assets.js'; then
            label="base"
        elif [ "$HAS_SPLIT" = "1" ] && printf '%s' "$command" | grep -q 'test/assets.js'; then
            label="assets"
        else
            label="test"
        fi

        rest="${command#nyc }"
        rest="${rest/mocha/mocha --forbid-only --no-bail}"

        run_test_suite "$label" "$REPOPATH/node_modules/.bin/nyc --reporter=lcov --reporter=text $rest" "false"
    done < <(printf '%s\n' "$TEST_DEF" | sed 's/ && /\n/g')
fi

print_header 2 "apostrophe coverage collection complete"
