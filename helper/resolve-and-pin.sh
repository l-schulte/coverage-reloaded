#!/bin/bash
# Resolve a hostname via getent and pin the resulting IPv4 address in
# /etc/hosts, retrying with exponential backoff. Used to stabilize flaky DNS
# (e.g. fastdl.mongodb.org on first resolution) so downloads during install /
# test runs don't fail with EAI_AGAIN. Source this file, then call
# resolve_and_pin "<hostname>".

resolve_and_pin() {
    local hostname="$1"
    local max_attempts="${2:-8}"
    local backoff="${3:-2}"
    local ip=""

    for i in $(seq 1 $max_attempts); do
        ip=$(getent ahostsv4 "$hostname" 2>/dev/null | awk '/STREAM/ { print $1; exit }')
        if [ -n "$ip" ]; then
            echo "$hostname resolved to $ip after $i attempt(s)"
            grep -v " $hostname$" /etc/hosts > /tmp/hosts.tmp \
                && cp /tmp/hosts.tmp /etc/hosts \
                && rm -f /tmp/hosts.tmp
            echo "$ip $hostname" >> /etc/hosts
            echo "$hostname pinned in /etc/hosts"
            return 0
        fi
        local wait=$(( backoff ** (i - 1) ))
        echo "DNS resolution attempt $i/$max_attempts for $hostname failed — retrying in ${wait}s"
        sleep $wait
    done

    echo "FATAL: cannot resolve $hostname after $max_attempts attempts"
    return 1
}
