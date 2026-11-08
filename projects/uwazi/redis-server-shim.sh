#!/bin/sh
# Wrapper installed by install-and-run.sh for the RedisServer / downloadRedis
# era (Oct 2021 - Sep 2022), in which the project's own tests spawn their own
# redis-server instances (for example `redis-server --port 6378`).
#
# The redis-server packaged in this image is built without the default save
# points that upstream's redis-stable carries (initServerConfig sets 3600/1,
# 300/100 and 60/10000).  A plain `redis-server --port N` therefore receives
# SIGINT and exits without writing dump.rdb, so the next start silently comes
# up with an empty dataset.  uwazi's `taskManager > should read pending
# messages` test writes a results message, restarts Redis and expects it to
# survive, and failed deterministically in every run of the era.
#
# The only difference from the packaged binary is the restored save points.
# Do not add --logfile or --dir here:
#   * --logfile redirects the child's log away from stdout, and the npm
#     `redis-server` package used until Oct 2021 resolves Server.open() by
#     reading "Ready to accept connections" from stdout, so every test file of
#     that era hangs.
#   * --dir changes where the shared dump.rdb lives relative to upstream CI and
#     leaks state between test files that spawn servers on the same port.
#
# The real binary is installed next to this file as redis-server.real.

set -u

real="$(dirname "$0")/redis-server.real"
if [ ! -x "$real" ]; then
    echo "redis-server shim: $real is missing or not executable" >&2
    exit 127
fi

exec "$real" "$@" --save 3600 1 --save 300 100 --save 60 10000
