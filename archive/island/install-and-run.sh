#!/bin/bash
set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/na-if-focus-marker.sh

export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=8192"
export NX_SKIP_NX_CACHE=true
export NX_DAEMON=false
export NX_NO_CLOUD=true
export NX_PARALLEL=16
export NX_MAX_PARALLEL=32
export JAVA_OPTS="${JAVA_OPTS:-} -Dlog.level=error"
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Dlog.level=error"

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    not_applicable "No package.json at this commit, no test infrastructure to run"
fi

# Exclude propertyDetail spec which contains a false-positive focus marker string
if [ -d libs ]; then
    na_if_focus_marker --exclude libs/api/domains/assets/src/models/propertyDetail.model.spec.ts libs
fi

print_header 2 "Installing dependencies"

if [ "$IS_YARN_MAIN_PM" = "true" ]; then
    if [ -f .yarnrc.yml ]; then
        if command -v corepack >/dev/null 2>&1; then
            corepack enable
        fi
        yarn install --immutable
    else
        yarn install --frozen-lockfile --ignore-engines
    fi
    PM_RUN="yarn run"
    PM_TEST="yarn test"
elif [ "$IS_NPM_MAIN_PM" = "true" ]; then
    npm install
    PM_RUN="npm run"
    PM_TEST="npm test"
elif [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    pnpm install
    PM_RUN="pnpm run"
    PM_TEST="pnpm test"
else
    print_header 2 "Unsupported package manager: $package_manager"
    exit 1
fi

HAS_CODEGEN=$(node -p "!!((require('./package.json').scripts||{}).codegen)")
HAS_SCHEMAS=$(node -p "!!((require('./package.json').scripts||{}).schemas)")
if [ "$HAS_CODEGEN" = "true" ]; then
    print_header 2 "Running codegen"
    LOG_LEVEL=warn $PM_RUN codegen
elif [ "$HAS_SCHEMAS" = "true" ]; then
    print_header 2 "Running schemas"
    LOG_LEVEL=warn $PM_RUN schemas
fi

source /coverage_reloaded/start-dind.sh

COVER_FLAG="--codeCoverage"
if [ -f .yarnrc.yml ]; then
    COVER_FLAG="--coverage"
fi

print_header 2 "Discovering test projects"

if $PM_RUN nx show projects --help >/dev/null 2>&1; then
    print_header 4 "Using nx show projects to discover testable projects"
    mapfile -t ALL_PROJECTS < <($PM_RUN nx show projects --with-target=test 2>/dev/null | grep -v '^>' | tr -d '\r' | sort -u)
elif [ -f workspace.json ]; then
    print_header 4 "Using workspace.json to discover testable projects"
    mapfile -t ALL_PROJECTS < <(node -p "Object.entries(require('./workspace.json').projects||{}).filter(([k,v]) => (v.architect||{}).test || (v.targets||{}).test).map(([k]) => k).join('\n')" | sort -u)
fi

TOTAL=${#ALL_PROJECTS[@]}
print_header 3 "Discovered $TOTAL test projects"
printf '%s\n' "${ALL_PROJECTS[@]}"

declare -A PROJ_DIR
while IFS="=" read -r name dir; do
    [ -n "$name" ] && PROJ_DIR["$name"]="$dir"
done < <(
    if [ -f workspace.json ]; then
        node -p "Object.entries(require('./workspace.json').projects||{}).map(([k,v]) => k + '=' + (typeof v === 'string' ? v : v.root)).join('\n')"
    else
        for pj in $(find apps libs -name "project.json"); do
            name=$(sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' "$pj" | head -1)
            [ -n "$name" ] && echo "$name=$(dirname "$pj")"
        done
    fi
)

TEST_PROJECTS=()
for pkg in "${ALL_PROJECTS[@]}"; do
    dir="${PROJ_DIR["$pkg"]:-}"
    [ -z "$dir" ] && continue
    if [ ! -f "$dir/jest.config.ts" ] && [ ! -f "$dir/jest.config.js" ]; then
        continue
    fi
    # Exclude external dependencies and e2e integration suites from unit test discovery
    SPEC_COUNT=$(find "$dir" \( -name "*.spec.[jt]s" -o -name "*.spec.[jt]sx" -o -name "*.test.[jt]s" -o -name "*.test.[jt]sx" -o -name "*.spec.mjs" \) -not -path "*/node_modules/*" -not -path "*/e2e/*" 2>/dev/null | wc -l)
    [ "$SPEC_COUNT" -eq 0 ] && continue
    TEST_PROJECTS+=("$pkg")
done

# Normalize coverageDirectory and fix skilavottord-web path alias in project jest configs
print_header 4 "Normalizing coverageDirectory in jest configs for ${#TEST_PROJECTS[@]} projects"
for pkg in "${TEST_PROJECTS[@]}"; do
    dir="${PROJ_DIR["$pkg"]:-}"
    [ -z "$dir" ] && continue
    cfg=$(ls "$dir"/jest.config.* 2>/dev/null | head -1)
    if [ -f "$cfg" ]; then
        node -e '
          const fs = require("fs");
          const p = process.argv[1];
          const d = process.argv[2];
          let s = fs.readFileSync(p, "utf8");
          if (/coverageDirectory:/.test(s)) {
            s = s.replace(/coverageDirectory:\s*[\x27\x22][^\x27\x22]+[\x27\x22]/, `coverageDirectory: "/coverage_reloaded/repo/coverage/${d}"`);
          } else {
            s = s.replace(/(module\.exports\s*=\s*\{|export\s+default\s*\{)/, `$1\n  coverageDirectory: "/coverage_reloaded/repo/coverage/${d}",`);
          }
          // Fix upstream typo in skilavottord-web where moduleNameMapper omits the /$1 capture group
          s = s.replace(/[\x27\x22]\^@island\.is\/skilavottord-web\/\(\.\*\)\$[\x27\x22]:\s*path\.resolve\(__dirname\)/, () => "\x27^@island.is/skilavottord-web/(.*)$\x27: `${path.resolve(__dirname)}/$1`");
          fs.writeFileSync(p, s);
        ' "$cfg" "$dir"
    fi
done

TARGETED_PROJECTS=()
LIGHT_PROJECTS=()
HEAVY_PROJECTS=()
for pkg in "${TEST_PROJECTS[@]}"; do
    # Targeted projects with non-standard setups or test fixtures (skilavottord-web, shared-babel)
    if [ "$pkg" = "skilavottord-web" ] || [ "$pkg" = "shared-babel" ]; then
        TARGETED_PROJECTS+=("$pkg")
        continue
    fi
    dir="${PROJ_DIR["$pkg"]:-}"
    # Exclude external dependencies and e2e integration suites from unit test discovery
    SPEC_COUNT=$(find "$dir" \( -name "*.spec.[jt]s" -o -name "*.spec.[jt]sx" -o -name "*.test.[jt]s" -o -name "*.test.[jt]sx" -o -name "*.spec.mjs" \) -not -path "*/node_modules/*" -not -path "*/e2e/*" 2>/dev/null | wc -l)
    if [ "$SPEC_COUNT" -ge 100 ]; then
        HEAVY_PROJECTS+=("$pkg")
    else
        LIGHT_PROJECTS+=("$pkg")
    fi
done

TOTAL_TESTABLE=${#TEST_PROJECTS[@]}
print_header 3 "Discovered $TOTAL_TESTABLE projects with test suites (${#TARGETED_PROJECTS[@]} targeted, ${#LIGHT_PROJECTS[@]} light, ${#HEAVY_PROJECTS[@]} heavy)"

verify_and_move_coverage() {
    local suite="$1"
    local suite_exit="$2"
    shift 2
    local -a projects=("$@")

    bash /coverage_reloaded/find-and-move-lcov.sh "$suite" "false" "$suite_exit"

    print_header 4 "Verifying coverage for ${#projects[@]} projects in $COVERAGE_REPORT_PATH"
    local missing=()
    for pkg in "${projects[@]}"; do
        local dir="${PROJ_DIR["$pkg"]:-}"
        [ -z "$dir" ] && continue
        if [ ! -s "$COVERAGE_REPORT_PATH/$dir/${suite}.lcov.info" ] && [ ! -s "$COVERAGE_REPORT_PATH/coverage/$dir/${suite}.lcov.info" ]; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        print_header 4 "ERROR: The following ${#missing[@]} projects crashed or failed to produce valid coverage:"
        printf '  - %s\n' "${missing[@]}"
        exit 1
    fi

    print_header 4 "Coverage verified successfully for all ${#projects[@]} projects"
    suite_end "$suite" "$suite_exit"
}

# Global fetch stub required by next-auth and api client suites under jsdom
cat << 'EOF' > /coverage_reloaded/repo/jest-setup-fetch.ts
if (typeof (global as any).fetch === 'undefined') {
  (global as any).fetch = (() =>
    Promise.resolve({
      ok: true,
      status: 200,
      json: () => Promise.resolve({}),
      text: () => Promise.resolve(''),
    })) as any;
  (global as any).Headers = class Headers {};
  (global as any).Request = class Request {};
  (global as any).Response = class Response {};
}
EOF

# Exclude test files from coverage instrumentation
JEST_COVERAGE_EXCLUDES="--collectCoverageFrom=!**/*.spec.* --collectCoverageFrom=!**/*.test.*"
# Exclude Vanilla Extract *.css.ts styling files
JEST_COVERAGE_EXCLUDES="$JEST_COVERAGE_EXCLUDES --collectCoverageFrom=!**/*.css.*"
# Exclude tooling configs, TypeScript declarations, infra, and DB migrations (matches upstream preset parity)
JEST_COVERAGE_EXCLUDES="$JEST_COVERAGE_EXCLUDES --collectCoverageFrom=!**/*.config.* --collectCoverageFrom=!**/*.d.ts --collectCoverageFrom=!**/infra/** --collectCoverageFrom=!**/seeders/** --collectCoverageFrom=!**/migrations/**"

JEST_FLAGS="--coverage --coverageReporters=lcov --collectCoverageFrom=**/*.{ts,tsx} $JEST_COVERAGE_EXCLUDES --setupFiles=/coverage_reloaded/repo/jest-setup-fetch.ts --forceExit"

if [ ${#TARGETED_PROJECTS[@]} -gt 0 ]; then
    suite_start "unit-targeted" "Running ${#TARGETED_PROJECTS[@]} targeted projects individually"
    SUITE_START=$SECONDS
    print_header 4 "Running ${#TARGETED_PROJECTS[@]} targeted projects individually"
    TARGETED_EXIT=0
    for pkg in "${TARGETED_PROJECTS[@]}"; do
        set +e
        if [ "$pkg" = "skilavottord-web" ]; then
            # Run skilavottord-web scoping coverage to tested utils, avoiding un-tested Next.js React UI trees
            $PM_RUN nx run skilavottord-web:test $COVER_FLAG -- --coverage --coverageReporters=lcov --collectCoverageFrom=apps/skilavottord/web/utils/**/*.{ts,tsx} --forceExit
        elif [ "$pkg" = "shared-babel" ]; then
            # Run shared-babel excluding AST test fixture with intentional duplicate exports
            $PM_RUN nx run shared-babel:test $COVER_FLAG -- --coverage --coverageReporters=lcov --collectCoverageFrom=libs/shared/babel/src/**/*.{ts,tsx} --collectCoverageFrom=!libs/shared/babel/src/exportFinder/test/fixture/** --collectCoverageFrom=!**/*.spec.* --collectCoverageFrom=!**/*.test.* --forceExit
        else
            $PM_RUN nx run "$pkg:test" $COVER_FLAG -- $JEST_FLAGS --maxWorkers=1
        fi
        PKG_EXIT=$?
        set -e
        [ "$PKG_EXIT" -ne 0 ] && TARGETED_EXIT="$PKG_EXIT"
    done
    print_header 4 "TIMING: unit-targeted completed in $((SECONDS - SUITE_START))s (exit_code=$TARGETED_EXIT)"
    verify_and_move_coverage "unit-targeted" "$TARGETED_EXIT" "${TARGETED_PROJECTS[@]}"
fi

if [ ${#LIGHT_PROJECTS[@]} -gt 0 ]; then
    suite_start "unit-light" "Running ${#LIGHT_PROJECTS[@]} lightweight projects in parallel"
    SUITE_START=$SECONDS
    LIGHT_CSV=$(IFS=, ; echo "${LIGHT_PROJECTS[*]}")
    print_header 4 "Running ${#LIGHT_PROJECTS[@]} lightweight projects in parallel"
    set +e
    $PM_RUN nx run-many --projects="$LIGHT_CSV" --target=test --parallel=8 --no-watchman --ci --passWithNoTests $COVER_FLAG -- $JEST_FLAGS --maxWorkers=1
    LIGHT_EXIT=$?
    set -e
    print_header 4 "TIMING: unit-light completed in $((SECONDS - SUITE_START))s (exit_code=$LIGHT_EXIT)"
    verify_and_move_coverage "unit-light" "$LIGHT_EXIT" "${LIGHT_PROJECTS[@]}"
fi

if [ ${#HEAVY_PROJECTS[@]} -gt 0 ]; then
    suite_start "unit-heavy" "Running ${#HEAVY_PROJECTS[@]} heavy projects in parallel"
    SUITE_START=$SECONDS
    HEAVY_CSV=$(IFS=, ; echo "${HEAVY_PROJECTS[*]}")
    print_header 4 "Running ${#HEAVY_PROJECTS[@]} heavy projects with dedicated worker pools"
    set +e
    $PM_RUN nx run-many --projects="$HEAVY_CSV" --target=test --parallel=2 --no-watchman --ci --passWithNoTests $COVER_FLAG -- $JEST_FLAGS --maxWorkers=6
    HEAVY_EXIT=$?
    set -e
    print_header 4 "TIMING: unit-heavy completed in $((SECONDS - SUITE_START))s (exit_code=$HEAVY_EXIT)"
    verify_and_move_coverage "unit-heavy" "$HEAVY_EXIT" "${HEAVY_PROJECTS[@]}"
fi
