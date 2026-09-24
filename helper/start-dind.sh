#!/bin/bash
# Shared helper to start Docker-in-Docker with multi-registry proxy caching and DNS configuration.
# Used by all projects requiring nested Docker (e.g. uwazi, opencrvs-core, rxdb).

set -e

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

print_header 2 "Starting Docker daemon (DinD)"

# Ensure daemon host resolution has reliable public DNS fallbacks
grep -q "nameserver 1.1.1.1" /etc/resolv.conf || echo "nameserver 1.1.1.1" >> /etc/resolv.conf
grep -q "nameserver 8.8.8.8" /etc/resolv.conf || echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Fetch and trust CA certificate if docker-multi-cache (or docker-cache) proxy is running on mining-net
PROXY_HOST=""
if curl -fsSL --connect-timeout 2 http://docker-multi-cache:3128/ca.crt -o /usr/local/share/ca-certificates/docker-registry-proxy.crt 2>/dev/null; then
    PROXY_HOST="docker-multi-cache"
elif curl -fsSL --connect-timeout 2 http://docker-cache:3128/ca.crt -o /usr/local/share/ca-certificates/docker-registry-proxy.crt 2>/dev/null; then
    PROXY_HOST="docker-cache"
fi

if [ -n "$PROXY_HOST" ]; then
    update-ca-certificates > /dev/null 2>&1 || true
    export HTTP_PROXY="http://${PROXY_HOST}:3128"
    export HTTPS_PROXY="http://${PROXY_HOST}:3128"
    export NO_PROXY="localhost,127.0.0.1,docker-cache,docker-multi-cache,waypack,verdaccio,pypi_cache,172.28.0.0/16"
    print_header 4 "Configured HTTPS proxy caching via http://${PROXY_HOST}:3128"
fi

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": ["http://docker-cache:5000"],
  "insecure-registries": ["http://docker-cache:5000"],
  "dns": ["1.1.1.1", "8.8.8.8"]
}
EOF

dockerd > /var/log/dockerd.log 2>&1 &
DOCKERD_PID=$!

for i in $(seq 1 30); do
    if docker ps > /dev/null 2>&1; then
        print_header 4 "Docker daemon ready (attempt $i)"
        break
    fi
    sleep 1
done

if ! docker ps > /dev/null 2>&1; then
    print_header 2 "DOCKER DAEMON FAILED" "Could not start Docker daemon within 30s. Check /var/log/dockerd.log for details."
    cat /var/log/dockerd.log
    exit 1
fi
