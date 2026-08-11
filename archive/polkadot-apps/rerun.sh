#!/bin/bash
# Rerun coverage collection for polkadot-apps commits.
# Reconstructs the `docker-run.sh ... exec ...` command (the same form that
# docker-run.sh prints as "Rerun with:" at the top of every log), so a single
# commit can be reproduced exactly.
#
# Usage:
#   ./rerun.sh <hash> [<hash> ...]     # rerun specific commit(s)
#   ./rerun.sh                          # rerun all current node:test-era .error commits
#                                        (the set this install-and-run.sh fix targets)
#
# Output logs go to projects/polkadot-apps/logs/ as docker-run.sh does.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJ=polkadot-apps
CSV="$ROOT/projects/$PROJ/commits.csv"
REPO="$ROOT/projects/$PROJ/repo"

cd "$ROOT" || exit 1

run_one() {
    local hash="$1"
    local line
    line=$(awk -F, -v h="$hash" '$1==h {print $2","$5","$3; exit}' "$CSV")
    if [ -z "$line" ]; then
        echo "SKIP: $hash not found in commits.csv"
        return 0
    fi
    local ts pm node
    ts=$(echo "$line"   | cut -d, -f1)
    pm=$(echo "$line"   | cut -d, -f2)
    node=$(echo "$line" | cut -d, -f3)

    echo "=== rerun $hash  (ts=$ts  pm=$pm  node=$node) ==="
    bash docker-run.sh "$PROJ" exec "$hash" "$ts" "$pm" "$node" "$PROJ" \
        2>&1 | tee >(strip-ansi > "projects/$PROJ/logs/${ts}_${hash}_$(date +"%Y%m%d_%H%M%S").log")
    echo "=== done $hash (exit of pipeline is tee's; inspect the .log / output/) ==="
}

if [ "$#" -ge 1 ]; then
    for h in "$@"; do
        run_one "$h"
    done
else
    echo "No hash given — rerunning all current node:test-era .error commits."
    for f in projects/$PROJ/output/*.error; do
        [ -e "$f" ] || continue
        base=$(basename "$f" .error)
        hash=${base#*_}
        era=$(git -C "$REPO" show "$hash:package.json" 2>/dev/null \
            | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const p=JSON.parse(s);const t=(p.scripts&&p.scripts.test)||"";process.stdout.write((/polkadot-dev-run-test .*--env |polkadot-exec-node-test/.test(t))?"node-test":"jest")}catch(e){process.stdout.write("unknown")}})')
        if [ "$era" = "node-test" ]; then
            run_one "$hash"
        fi
    done
fi
