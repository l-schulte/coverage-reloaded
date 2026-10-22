#!/bin/bash
set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/assert-suite-ran.sh
source /coverage_reloaded/na-if-focus-marker.sh

cd /coverage_reloaded/repo

print_header 1 "sequelize — coverage collection" "revision $revision"

COVER=(npx --yes --registry="$WAYPACK_REGISTRY_CURRENT" c8 --reporter=lcovonly --)

# The project's own per-test DB reset (clearDatabase -> dropAllTables) removes
# every foreign key and every table one at a time, so on the container dialects
# (mssql/db2/mysql) it can exceed the test-support default CLEANUP_TIMEOUT of 10s
# and be recorded as "Could not clear database ... crashed the DB" — or, when it
# runs in a beforeAll, as a zero-test abort. The project reads this override
# itself (packages/core/test/integration/support.ts); 2 minutes is well under the
# 20 minutes the project's own CI used for this variable when DB2 support landed
# (.github/workflows/ci.yml, 4443d2af1). It lets a slow-but-alive reset finish;
# a genuinely dead DB still fails, just later.
CLEANUP_TIMEOUT_MS=120000

# DB2's clidriver is fetched outside npm/WayPack, so pin it per era. The
# discriminator is the exact string the project added when it moved to
# ibm_db 3.3.0 (PR #17737): the newer clidriver prefixes SQL0803N with it.
if grep -rqs 'An error or warning occurred' packages/db2/src lib/dialects/db2; then
    export IBM_DB_INSTALLER_URL=/opt/ibm-clidriver/v12
else
    export IBM_DB_INSTALLER_URL=/opt/ibm-clidriver/v11
fi

if [ "$IS_NPM_MAIN_PM" = "true" ]; then
    PM_RUN=(npm run)
elif [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    PM_RUN=(pnpm run)
else
    PM_RUN=(yarn run)
fi

HAS_WORKSPACES=$(node -p "typeof require('./package.json').workspaces !== 'undefined'")
print_header 4 "monorepo (workspaces): $HAS_WORKSPACES"

if [ "$HAS_WORKSPACES" = "true" ] && [ -f packages/core/package.json ]; then
    CORE_PKG=packages/core/package.json
    CORE_DIR=packages/core
else
    CORE_PKG=package.json
    CORE_DIR=.
fi

FOCUS_PATHS=()
for p in test packages; do
    [ -d "$p" ] && FOCUS_PATHS+=("$p")
done
if [ "${#FOCUS_PATHS[@]}" -gt 0 ]; then
    # sequelize runs its suites under mocha, whose .only is run-global: a
    # committed marker truncates the entire run, so such a commit is
    # not-applicable rather than measured (see helper/na-if-focus-marker.sh).
    na_if_focus_marker --runner mocha "${FOCUS_PATHS[@]}"
fi

print_header 2 "Installing dependencies"
if [ "$IS_NPM_MAIN_PM" = "true" ]; then
    npm install --no-fund
elif [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    pnpm install --no-frozen-lockfile
else
    YARN_ENABLE_IMMUTABLE_INSTALLS=false yarn install
fi

if [ "$HAS_WORKSPACES" = "true" ] && node -e "process.exit(require('./package.json').scripts.build ? 0 : 1)" 2>/dev/null; then
    print_header 2 "Building workspace packages"
    yarn build
fi

VIABLE_DIALECTS="${SEQUELIZE_VIABLE_DIALECTS:-sqlite sqlite3 mariadb mysql postgres postgres-native mssql db2 oracle}"
SKIPPABLE_DIALECTS="${SEQUELIZE_SKIPPABLE_DIALECTS:-ibmi snowflake}"

dialect_viable() {
    case " $VIABLE_DIALECTS " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

dialect_skippable() {
    case " $SKIPPABLE_DIALECTS " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

print_header 4 "viable dialects: $VIABLE_DIALECTS"
print_header 4 "skippable dialects: $SKIPPABLE_DIALECTS"

DB_ERA=none
if compgen -G "dev/*/docker-compose.yml" >/dev/null || compgen -G "dev/*/*/docker-compose.yml" >/dev/null; then
    DB_ERA=dev
elif [ -f docker-compose.yml ]; then
    DB_ERA=rootcompose
fi
print_header 4 "database provisioning era: $DB_ERA"

# The pre-monorepo dev/<db>/<ver>/start.sh scripts end with
# `DIALECT=<db> node check.js`, and check.js requires the commit's test-support.
# Plain `node` cannot load it: support imports the library by package name (the
# `sequelize` -> dist alias) and/or is TypeScript, and in the 2022-04..2022-06
# window it also calls the Mocha globals (afterEach/before/beforeEach) unguarded
# at module scope. The project only made all of that safe on 2022-06-09 (#14608),
# which replaced check.js with a ts-node `check-connection.ts` and guarded the
# globals. Upstream CI never ran these scripts (it started the DBs via Actions
# `services:`), so it never hit this. For the window where test/registerEsbuild.js
# and a dev/**/check.js both exist, preload a shim that provides no-op Mocha
# globals and then the project's own mocha loader.
DEV_CHECK_PRELOAD=""
if [ -f test/registerEsbuild.js ] && [ -d dev ] && [ -n "$(find dev -name check.js -print -quit)" ]; then
    DEV_CHECK_PRELOAD="$(mktemp /tmp/sequelize-db-check-preload.XXXXXX.js)"
    cat > "$DEV_CHECK_PRELOAD" <<EOF
'use strict';
for (const g of ['afterEach', 'beforeEach', 'before', 'after', 'describe', 'it']) {
  if (typeof global[g] === 'undefined') {
    global[g] = () => {};
  }
}
require('$REPOPATH/test/registerEsbuild');
EOF
fi
print_header 4 "preload shim for db start checks: ${DEV_CHECK_PRELOAD:-none}"

stop_database_containers() {
    local ids
    ids=$(docker ps -aq 2>/dev/null || true)
    if [ -n "$ids" ]; then
        print_header 3 "Stopping database containers"
        docker rm -f $ids >/dev/null 2>&1 || true
    fi
}

dump_db_diagnostics() {
    # Called only after a DB failed to become healthy. Prints the container
    # state, its health-probe history and the server's own startup log so the
    # real cause (crash / probe mismatch / accumulated state) is visible in the
    # run log instead of only "not healthy within Ns". Best-effort: these probes
    # must never mask or replace the original failure, so they run under an
    # explicit set +e and the caller re-raises the DB-start exit code afterwards.
    local db="$1"
    print_header 2 "DB diagnostics for '$db' (did not become healthy)"
    set +e
    print_header 4 "docker ps -a"
    docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
    local cid name
    for cid in $(docker ps -aq); do
        name=$(docker inspect -f '{{.Name}}' "$cid")
        print_header 4 "docker inspect $name .State"
        docker inspect -f '{{json .State}}' "$cid"
        print_header 4 "docker inspect $name .State.Health"
        docker inspect -f '{{json .State.Health}}' "$cid"
        print_header 4 "docker logs --tail 150 $name"
        docker logs --tail 150 "$cid"
    done
    set -e
}

wait_for_db_ready() {
    # Docker's userland proxy accepts the published port before the database is
    # ready, so a host-port check returns immediately and the tests connect too
    # early. Probe the database's own listening port inside the container instead.
    local db="$1"
    local service="$2"
    local timeout="$3"
    local internal_port
    case "$db" in
        mysql | mariadb) internal_port=3306 ;;
        postgres | postgres-native) internal_port=5432 ;;
        mssql) internal_port=1433 ;;
        *)
            print_header 2 "ERROR: no readiness probe for dialect '$db'"
            return 1
            ;;
    esac
    local cid
    cid=$(docker compose -f docker-compose.yml ps -q "$service" 2>/dev/null | head -1)
    if [ -z "$cid" ]; then
        print_header 2 "ERROR: no running container for service '$service'"
        return 1
    fi
    local waited=0
    until docker exec "$cid" bash -c "exec 3<>/dev/tcp/127.0.0.1/${internal_port}" >/dev/null 2>&1; do
        if [ "$waited" -ge "$timeout" ]; then
            print_header 2 "ERROR: $db ($service) not accepting connections within ${timeout}s"
            return 1
        fi
        sleep 3
        waited=$((waited + 3))
    done
    print_header 4 "NOTICE: $db ($service) accepting connections after ${waited}s"
}

select_db_start_script() {
    node -e '
        const db = process.argv[1];
        const scripts = require("./package.json").scripts || {};
        const prefix = "start-" + db;
        const names = Object.keys(scripts).filter(k => k === prefix || k.startsWith(prefix + "-"));
        const rank = n => {
            const suffix = n.slice(prefix.length);
            let version = "0";
            if (suffix === "-latest") version = "999999";
            else if (suffix === "-oldest") version = "0";
            else if (suffix.startsWith("-")) version = suffix.slice(1);
            else {
                const m = (scripts[n] || "").match(new RegExp("dev/" + db + "/([^/]+)/start\\.sh"));
                version = m ? m[1] : "0";
            }
            return (version.match(/[0-9]+(\.[0-9]+)*/) || ["0"])[0];
        };
        const rows = names.map(n => ({ n, v: rank(n) }));
        rows.sort((a, b) => a.v.localeCompare(b.v, undefined, { numeric: true }));
        process.stdout.write(rows.length ? rows[rows.length - 1].n : "");
    ' "$1"
}

ROOT_SERVICE_mysql=mysql-57
ROOT_SERVICE_mariadb=mariadb-103
ROOT_SERVICE_postgres=postgres-10
ROOT_SERVICE_postgres_native=postgres-95
ROOT_SERVICE_mssql=mssql

start_database() {
    local db="$1"
    case "$db" in
        sqlite | sqlite3) return 0 ;;
    esac

    case "$DB_ERA" in
        dev)
            local lookup="$db"
            if [ "$lookup" = "postgres-native" ]; then
                lookup="postgres"
            fi
            local script
            script=$(select_db_start_script "$lookup")
            if [ -z "$script" ]; then
                print_header 2 "ERROR: no start-<db> script found for dialect '$db'"
                return 1
            fi
            print_header 3 "Starting $db via '$script'"
            set +e
            if [ -n "$DEV_CHECK_PRELOAD" ]; then
                print_header 4 "NOTICE: preloading $DEV_CHECK_PRELOAD for '$script' (its 'node check.js' loads test/support outside mocha)"
                env DIALECT="$db" NODE_OPTIONS="--require $DEV_CHECK_PRELOAD" "${PM_RUN[@]}" "$script"
            else
                env DIALECT="$db" "${PM_RUN[@]}" "$script"
            fi
            local start_rc=$?
            set -e
            if [ "$start_rc" -ne 0 ]; then
                print_header 4 "NOTICE: '$script' exited $start_rc; sleeping 10s and retrying once..."
                sleep 10
                set +e
                if [ -n "$DEV_CHECK_PRELOAD" ]; then
                    env DIALECT="$db" NODE_OPTIONS="--require $DEV_CHECK_PRELOAD" "${PM_RUN[@]}" "$script"
                else
                    env DIALECT="$db" "${PM_RUN[@]}" "$script"
                fi
                start_rc=$?
                set -e
            fi
            if [ "$start_rc" -ne 0 ]; then
                dump_db_diagnostics "$db"
                return "$start_rc"
            fi
            ;;
        rootcompose)
            local service_var service
            service_var="ROOT_SERVICE_$(printf '%s' "$db" | tr '-' '_')"
            service="${!service_var:-}"
            if [ -z "$service" ]; then
                print_header 2 "ERROR: no root-compose service for dialect '$db'"
                return 1
            fi
            print_header 3 "Starting $db via root docker-compose.yml (service $service)"
            export MYSQLDB_ENTRYPOINT="$REPOPATH/test/config/mysql"
            export MARIADB_ENTRYPOINT="$REPOPATH/test/config/mariadb"
            docker compose -f docker-compose.yml up -d "$service"
            if ! wait_for_db_ready "$db" "$service" 300; then
                dump_db_diagnostics "$db"
                return 1
            fi
            if [ "$db" = "mssql" ]; then
                local cid
                cid=$(docker compose -f docker-compose.yml ps -q "$service" | head -1)
                print_header 3 "Creating 'sequelize_test' database on mssql"
                docker exec "$cid" /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "yourStrong(!)Password" \
                    -Q "IF DB_ID('sequelize_test') IS NULL CREATE DATABASE sequelize_test; ALTER DATABASE sequelize_test SET READ_COMMITTED_SNAPSHOT ON;"
            fi
            ;;
        *)
            print_header 2 "ERROR: no database provisioning mechanism for dialect '$db'"
            return 1
            ;;
    esac
}

dialect_env() {
    if [ "$DB_ERA" = "dev" ]; then
        return 0
    fi
    echo "SEQ_DB=sequelize_test"
    echo "SEQ_USER=sequelize_test"
    echo "SEQ_PW=sequelize_test"
    echo "SEQ_HOST=127.0.0.1"
    case "$1" in
        mysql) echo "SEQ_MYSQL_PORT=8980" ;;
        mariadb) echo "SEQ_MARIADB_PORT=8960" ;;
        postgres) echo "SEQ_PG_PORT=8991" ;;
        postgres-native) echo "SEQ_PG_PORT=8990" ;;
        mssql)
            echo "SEQ_MSSQL_PORT=8970"
            echo "SEQ_MSSQL_DB=sequelize_test"
            echo "SEQ_MSSQL_USER=sa"
            echo "SEQ_MSSQL_PW=yourStrong(!)Password"
            ;;
    esac
}

run_suite() {
    local suite_name="$1"
    local dialect="$2"
    local dir="$3"
    shift 3
    local -a cmd=("$@")

    local -a envs=("SEQ_TEST_CLEANUP_TIMEOUT=$CLEANUP_TIMEOUT_MS")
    if [ -n "$dialect" ]; then
        while IFS= read -r kv; do
            envs+=("$kv")
        done < <(dialect_env "$dialect")
        envs+=("DIALECT=$dialect")
    fi

    local log_file
    log_file=$(mktemp)
    suite_start "$suite_name" "dialect=${dialect:-none} dir=$dir"
    set +e
    ( cd "$dir" && env "${envs[@]}" "${COVER[@]}" "${cmd[@]}" ) | tee "$log_file"
    local test_exit=${PIPESTATUS[0]}
    set -e
    assert_suite_ran "$suite_name" mocha "$log_file" "$test_exit"
    rm -f "$log_file"
    bash /coverage_reloaded/find-and-move-lcov.sh "$suite_name" "true" "$test_exit"
    suite_end "$suite_name" "$test_exit"
}

UNIT_DIALECTS=$(node -p "Object.keys(require('./$CORE_PKG').scripts||{}).filter(k=>/^test-unit-/.test(k)&&k!=='test-unit-all').map(k=>k.replace('test-unit-','')).join(' ')")
INTEGRATION_DIALECTS=$(node -p "Object.keys(require('./$CORE_PKG').scripts||{}).filter(k=>/^test-integration-/.test(k)&&k!=='test-integration-all').map(k=>k.replace('test-integration-','')).join(' ')")
print_header 4 "unit dialects: ${UNIT_DIALECTS:-none}"
print_header 4 "integration dialects: ${INTEGRATION_DIALECTS:-none}"

# Suite availability is decided by the package that owns the script, NOT by the
# repo layout: `test-smoke` also exists at the root during the single-package
# era (2022-02-24 -> 2023-01-15), so it must not be gated on HAS_WORKSPACES.
HAS_UNIT_ESM=false
if node -e "process.exit(require('./package.json').scripts['test-unit-esm'] ? 0 : 1)" 2>/dev/null; then
    HAS_UNIT_ESM=true
fi

HAS_SMOKE=false
if node -e "process.exit(require('./$CORE_PKG').scripts['test-smoke'] ? 0 : 1)" 2>/dev/null; then
    HAS_SMOKE=true
fi

install_pg_native() {
    if ( cd "$CORE_DIR" && node -e "require.resolve('pg-native')" ) >/dev/null 2>&1; then
        return 0
    fi
    print_header 3 "Installing pg-native (postgres-native dialect)"
    if [ "$IS_NPM_MAIN_PM" = "true" ]; then
        ( cd "$CORE_DIR" && npm install --no-save pg-native )
    else
        ( cd "$CORE_DIR" && yarn add --dev pg-native )
    fi
}

case " $INTEGRATION_DIALECTS " in
    *" postgres-native "*)
        install_pg_native
        ;;
esac

DB_REPLACE_RULES=(
    'mcr.microsoft.com/mssql/server:2022-latest|mcr.microsoft.com/mssql/server:2022-CU13-ubuntu-22.04|/opt/mssql-tools/bin/sqlcmd'
    'mcr.microsoft.com/mssql/server:2019-latest|mcr.microsoft.com/mssql/server:2019-CU18-ubuntu-20.04|/opt/mssql-tools/bin/sqlcmd'
    'microsoft/mssql-server-linux:latest|mcr.microsoft.com/mssql/server:2017-latest|'
    'ibmcom/db2-amd64:11.5.6.0a|ibmcom/db2-amd64:11.5.8.0|'
    'ibmcom/db2-amd64:11.5.7.0|ibmcom/db2-amd64:11.5.8.0|'
)

db_replace() {
    # Image substitutions keyed on exact references: OLD|NEW|REQUIRE. REQUIRE,
    # when set, must also appear in the file for the substitution to apply.
    local rule old new require f
    for rule in "${DB_REPLACE_RULES[@]}"; do
        IFS='|' read -r old new require <<< "$rule"
        [ -z "$old" ] && continue
        while IFS= read -r f; do
            grep -qF "$old" "$f" || continue
            if [ -n "$require" ] && ! grep -qF "$require" "$f"; then
                continue
            fi
            print_header 4 "NOTICE: db_replace in $f: '$old' -> '$new'"
            sed -i "s#$(printf '%s' "$old" | sed 's/\./\\./g')#${new}#g" "$f"
        done < <(find . \( -name node_modules -o -name .git \) -prune -o -type f \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'start.sh' \) -print 2>/dev/null)
    done
}

relax_db_healthcheck_timeouts() {
    # The project's DB healthchecks use `timeout: 1s`, which kills the probe
    # (sqlcmd / mysqladmin / pg_isready) before it can return under load, so the
    # container can never report healthy and the start script times out. Relax
    # every healthcheck timeout to 30s. Fails loudly on any unexpected layout.
    local -a files=()
    if [ -d dev ]; then
        while IFS= read -r f; do files+=("$f"); done < <(find dev -name docker-compose.yml | sort)
    fi
    if [ -f docker-compose.yml ]; then
        files+=("docker-compose.yml")
    fi
    if [ "${#files[@]}" -eq 0 ]; then
        print_header 2 "ERROR: no docker-compose.yml found to relax healthcheck timeouts"
        exit 1
    fi
    print_header 3 "Relaxing DB healthcheck timeouts to 30s"
    node - "${files[@]}" <<'NODE'
const fs = require('fs');
const files = process.argv.slice(2);
const indentOf = l => (l.match(/^[ \t]*/) || [''])[0].length;
const isIgnorable = l => l.trim() === '' || l.trim().startsWith('#');
let blocks = 0, changed = 0;
for (const file of files) {
  const raw = fs.readFileSync(file, 'utf8');
  const out = [];
  let hcIndent = null, hcTimeout = false;
  const closeBlock = () => {
    if (hcIndent !== null && !hcTimeout) {
      console.error(`[ERR] ${file}: healthcheck block has no 'timeout:' line (unexpected layout)`);
      process.exitCode = 1;
    }
  };
  for (const line of raw.split('\n')) {
    const ind = indentOf(line);
    if (hcIndent !== null && !isIgnorable(line) && ind <= hcIndent) {
      closeBlock();
      hcIndent = null; hcTimeout = false;
    }
    if (hcIndent === null && /^[ \t]*healthcheck:[ \t]*$/.test(line)) {
      hcIndent = ind; hcTimeout = false; blocks++;
      out.push(line); continue;
    }
    if (hcIndent !== null && ind > hcIndent && /^[ \t]*timeout:/.test(line)) {
      if (hcTimeout) {
        console.error(`[ERR] ${file}: duplicate 'timeout:' inside one healthcheck block`);
        process.exitCode = 1;
      }
      const prefix = line.slice(0, line.indexOf('timeout:'));
      if (!/^[ \t]*timeout:[ \t]*30s[ \t]*$/.test(line)) changed++;
      out.push(`${prefix}timeout: 30s`);
      hcTimeout = true; continue;
    }
    if (hcIndent === null && /^[ \t]*timeout:/.test(line)) {
      console.error(`[ERR] ${file}: 'timeout:' outside a healthcheck block (unexpected layout)`);
      process.exitCode = 1;
    }
    out.push(line);
  }
  closeBlock();
  const next = out.join('\n');
  if (next !== raw) fs.writeFileSync(file, next);
}
if (process.exitCode) {
  console.error('[ERR] healthcheck timeout patch aborted: unexpected compose layout');
  process.exit(1);
}
console.log(`[NFO] healthcheck timeouts set to 30s: ${files.length} compose file(s), ${blocks} healthcheck block(s), ${changed} changed`);
NODE
}

disable_innodb_native_aio() {
    # MySQL/MariaDB allocate a Linux native-AIO context at startup whose size scales
    # with the number of CPUs the container sees (innodb_read_io_threads defaults to
    # ncpu/2). On a large shared host the host-wide fs.aio-max-nr budget is consumed
    # by a few concurrent instances, io_setup() then fails with EAGAIN and the engine
    # aborts at boot (`InnoDB: io_setup() failed with EAGAIN`) -> hard error. Setting
    # innodb_use_native_aio=0 makes InnoDB use simulated AIO and never call io_setup().
    # The option exists in every engine version in the study range (MySQL 5.7-8.4,
    # MariaDB 10.3-11.6) and the official images prepend the server binary when the
    # first argument starts with '-' (docker-entrypoint.sh: `set -- mysqld "$@"` /
    # `set -- mariadbd "$@"`). Injects a `command:` into each mysql/mariadb service;
    # fails loudly on an unexpected compose layout.
    local -a files=()
    if [ -d dev ]; then
        while IFS= read -r f; do files+=("$f"); done < <(find dev -name docker-compose.yml | sort)
    fi
    if [ -f docker-compose.yml ]; then
        files+=("docker-compose.yml")
    fi
    if [ "${#files[@]}" -eq 0 ]; then
        print_header 4 "NOTICE: no docker-compose.yml to patch for InnoDB native AIO"
        return 0
    fi
    print_header 3 "Disabling InnoDB native AIO in mysql/mariadb services"
    node /opt/aio-patch/disable-innodb-native-aio.js "${files[@]}"
}

extend_health_wait() {
    # dev/<db>/<ver>/start.sh gate on dev/wait-until-healthy.sh. The pre-2024
    # form waits only 20s (50 x 0.4s), too short for a first DB init; extend it
    # to 120s. The 2024+ form already waits ~170s. Fails loudly if unexpected.
    local helper=dev/wait-until-healthy.sh
    if [ ! -f "$helper" ]; then
        if grep -rqs 'wait-until-healthy' dev 2>/dev/null; then
            print_header 2 "ERROR: dev start scripts reference wait-until-healthy.sh but it is missing" "expected: $helper"
            exit 1
        fi
        print_header 4 "NOTICE: no $helper at this commit (pre-dev era); nothing to extend"
        return 0
    fi
    if grep -q 'sleep 1' "$helper"; then
        if ! grep -q 'for _ in {1..50}' "$helper"; then
            print_header 2 "ERROR: $helper is the 2024+ form but its loop is not 'for _ in {1..50}' as expected"
            exit 1
        fi
        print_header 4 "NOTICE: $helper already waits ~170s (2024+ form); not extended"
        return 0
    fi
    if ! grep -q 'for _ in {1..50}' "$helper" || ! grep -q 'sleep 0.4' "$helper"; then
        print_header 2 "ERROR: $helper has an unexpected legacy form; refusing to patch its wait" "expected 'for _ in {1..50}' and 'sleep 0.4'"
        exit 1
    fi
    print_header 3 "Extending legacy DB health wait 20s -> 120s in $helper"
    sed -i 's/for _ in {1\.\.50}/for _ in {1..300}/' "$helper"
    if ! grep -q 'for _ in {1..300}' "$helper"; then
        print_header 2 "ERROR: failed to extend the health wait in $helper"
        exit 1
    fi
}

neutralize_rootcompose_mssql_json() {
    # rootcompose era only: test/config/config.js prefers test/config/mssql.json when
    # present. The 21 commits of 2021-01-15..17 ship that file with a hard-coded port
    # 1433 (and SA/Password12!), overriding the harness env and the root compose's
    # published port 8970 (sa/yourStrong(!)Password). Renaming it aside makes config.js
    # fall back to the env (SEQ_MSSQL_HOST/PORT/USER/PW), which matches the compose.
    # No-op in the dev era and in the 42 later rootcompose commits (file absent). The
    # repo is a throwaway copy, so the file is not restored.
    if [ "$DB_ERA" != "rootcompose" ]; then
        return 0
    fi
    local f=test/config/mssql.json
    if [ ! -f "$f" ]; then
        return 0
    fi
    print_header 3 "Neutralizing $f so rootcompose mssql uses SEQ_MSSQL_PORT"
    mv "$f" "$f.co_re_disabled"
    print_header 4 "NOTICE: moved $f -> $f.co_re_disabled"
}

db_replace
relax_db_healthcheck_timeouts
disable_innodb_native_aio
neutralize_rootcompose_mssql_json
extend_health_wait

for d in $INTEGRATION_DIALECTS; do
    case "$d" in
        sqlite | sqlite3) ;;
        *) if dialect_viable "$d"; then source /coverage_reloaded/start-dind.sh; break; fi ;;
    esac
done

for d in $UNIT_DIALECTS; do
    run_suite "unit-$d" "$d" "$CORE_DIR" "${PM_RUN[@]}" "test-unit-$d"
done

if [ "$HAS_UNIT_ESM" = "true" ]; then
    run_suite "unit-esm" "" "." "${PM_RUN[@]}" "test-unit-esm"
fi

for d in $INTEGRATION_DIALECTS; do
    if ! dialect_viable "$d"; then
        if dialect_skippable "$d"; then
            print_header 4 "NOTICE: integration dialect '$d' is on the skippable list — not run"
            continue
        fi
        print_header 2 "ERROR: unexpected integration dialect '$d'" "no local backend and not on the skippable list"
        exit 1
    fi
    start_database "$d"
    run_suite "integration-$d" "$d" "$CORE_DIR" "${PM_RUN[@]}" "test-integration-$d"
    if [ "$HAS_SMOKE" = "true" ]; then
        run_suite "smoke-$d" "$d" "$CORE_DIR" "${PM_RUN[@]}" "test-smoke"
    fi
    stop_database_containers
done

if [ "$HAS_WORKSPACES" = "true" ]; then
    for pkg_json in packages/*/package.json; do
        [ -f "$pkg_json" ] || continue
        pkg_dir=$(dirname "$pkg_json")
        [ "$pkg_dir" = "$CORE_DIR" ] && continue
        if node -e "process.exit(require('./$pkg_json').scripts['test-unit'] ? 0 : 1)" 2>/dev/null; then
            run_suite "unit-pkg-$(basename "$pkg_dir")" "" "$pkg_dir" "${PM_RUN[@]}" "test-unit"
        fi
    done
fi

print_header 1 "sequelize coverage collection complete"
