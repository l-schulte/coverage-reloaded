#!/bin/bash
# opencrvs-core: host-side warm-up for the `docker-multi-cache` pull-through proxy
# on mining-net (waypack-machine/docker-compose.yaml -> rpardini/docker-registry-proxy).
# Project-specific: the image list below is exactly what opencrvs-core's behavioral
# suite starts across its full commit history.
#
# Why: every coverage run starts a fresh Docker-in-Docker daemon, so testcontainers
# (redis / postgres / elasticsearch / ryuk) re-pulls its images on every commit.
# Those pulls go through docker-multi-cache; when the proxy cache is cold for a blob
# it must fetch from the upstream registry over the flaky campus egress, which is
# what produced the `Get "https://registry-1.docker.io/v2/": context deadline
# exceeded` hard errors (and infra-induced test failures) in opencrvs-core.
#
# This script pulls each image ONCE, through the proxy, so its manifests and layer
# blobs land in the proxy's persistent cache volume (`docker_multi_cache_data`).
# Afterwards every run's pull is a LAN-speed cache hit with no upstream dependency.
# Run it again any time (e.g. after adding new image tags, or after a cache wipe).
#
# Usage:
#   bash projects/opencrvs-core/warm-docker-cache.sh            # warm the image set
#   bash projects/opencrvs-core/warm-docker-cache.sh <img>...   # warm specific images
#
# Mechanism: rootless podman into a throwaway image store (deleted afterwards, so
# each invocation genuinely re-fetches through the proxy), with the proxy's MITM CA
# trusted per registry host via containers certs.d — TLS verification stays ON.
# Proxy: HTTPS_PROXY=http://localhost:3128 (published port of docker-multi-cache).
#
# Image set = the images the opencrvs-core behavioral suite starts across its full
# commit history (enumerated from the repo history):
#   packages/gateway  GenericContainer('redis:5' | 'redis:8')
#   packages/events   ElasticsearchContainer('elasticsearch:8.14.3' | 'elasticsearch:8.16.4')
#                     PostgreSqlContainer('postgres:17' | 'postgres:17.6')
#   packages/search   ElasticsearchContainer('elasticsearch:8.14.3' | 'elasticsearch:8.16.4')
#   reaper (ryuk), per testcontainers release used (9.12.0 / 10.15.0 -> 0.5.1,
#   11.0.3 -> 0.11.0)
# Passing images as arguments overrides the list (e.g. to re-warm a single one).

set -euo pipefail

PROXY_URL="${DOCKER_MULTI_CACHE_URL:-http://localhost:3128}"
CERTS_DIR="${CONTAINERS_CERTS_DIR:-$HOME/.config/containers/certs.d}"
PULL_ATTEMPTS=3

DEFAULT_IMAGES=(
    "docker.io/library/redis:5"
    "docker.io/library/redis:8"
    "docker.io/library/postgres:17"
    "docker.io/library/postgres:17.6"
    "docker.io/library/elasticsearch:8.14.3"
    "docker.io/library/elasticsearch:8.16.4"
    "docker.io/testcontainers/ryuk:0.5.1"
    "docker.io/testcontainers/ryuk:0.11.0"
)

if [ "$#" -gt 0 ]; then
    IMAGES=("$@")
else
    IMAGES=("${DEFAULT_IMAGES[@]}")
fi

echo "[warm-docker-cache] proxy: $PROXY_URL"

# 1. Fetch the proxy's MITM CA. Failure here is fatal and loud: without the CA the
#    pulls would either fail TLS verification or fall back to direct upstream
#    access, which is exactly the failure mode we are eliminating.
CA_FILE="$(mktemp /tmp/opencode/proxy-ca.XXXXXX.crt)"
if ! curl -fsSL --connect-timeout 5 "$PROXY_URL/ca.crt" -o "$CA_FILE"; then
    echo "[warm-docker-cache] ERROR: cannot fetch proxy CA from $PROXY_URL/ca.crt — is docker-multi-cache running on mining-net?" >&2
    exit 1
fi
echo "[warm-docker-cache] CA fetched: $(openssl x509 -in "$CA_FILE" -noout -subject | sed 's/^subject=//')"

# 2. Trust the CA per registry host (containers certs.d). TLS verification stays on.
for host in docker.io registry-1.docker.io auth.docker.io; do
    mkdir -p "$CERTS_DIR/$host"
    cp "$CA_FILE" "$CERTS_DIR/$host/ca.crt"
done
echo "[warm-docker-cache] CA installed under $CERTS_DIR for docker.io, registry-1.docker.io, auth.docker.io"

# 3. Pull each image through the proxy into a throwaway store. The store is deleted
#    afterwards so every invocation genuinely re-fetches through the proxy. Rootless
#    podman storage contains files owned by mapped container UIDs, so removal must
#    run inside the user namespace (`podman unshare rm -rf`); if that still fails,
#    the directory is left in place with a warning and the warm-up result stands.
STORE="$(mktemp -d /tmp/opencode/warm-docker-cache.XXXXXX)"
cleanup() {
    local rc=$?
    set +e
    if [ -d "$STORE" ]; then
        podman unshare rm -rf "$STORE"
        if [ -d "$STORE" ]; then
            echo "[warm-docker-cache] WARNING: could not remove throwaway store $STORE (left in place)" >&2
        fi
    fi
    rm -f "$CA_FILE"
    exit "$rc"
}
trap cleanup EXIT

failed=()
for image in "${IMAGES[@]}"; do
    ok=false
    for attempt in $(seq 1 "$PULL_ATTEMPTS"); do
        echo "[warm-docker-cache] pull $image (attempt $attempt/$PULL_ATTEMPTS)"
        set +e
        HTTPS_PROXY="$PROXY_URL" HTTP_PROXY="$PROXY_URL" \
            podman --root "$STORE/root" --runroot "$STORE/runroot" pull "$image"
        rc=$?
        set -e
        if [ "$rc" -eq 0 ]; then
            ok=true
            break
        fi
        echo "[warm-docker-cache] WARNING: pull of $image failed with exit code $rc (attempt $attempt/$PULL_ATTEMPTS)" >&2
    done
    if [ "$ok" = true ]; then
        echo "[warm-docker-cache] warmed: $image"
    else
        echo "[warm-docker-cache] ERROR: could not warm $image after $PULL_ATTEMPTS attempts" >&2
        failed+=("$image")
    fi
done

# 4. Summary. Non-zero exit if anything failed — the caller must not assume warm.
if [ "${#failed[@]}" -gt 0 ]; then
    echo "[warm-docker-cache] FAILED to warm ${#failed[@]} image(s): ${failed[*]}" >&2
    exit 1
fi
echo "[warm-docker-cache] all ${#IMAGES[@]} image(s) warmed through $PROXY_URL"
