fake_time() {
    # --
    # Fakes the system time for a command using libfaketime.
    # The timestamp to fake is provided via the $timestamp environment variable.
    # Usage: fake_time <command>
    # Example: timestamp=1700000000 fake_time date
    # --
    if [ -z "$timestamp" ]; then
        echo "ERROR: timestamp is not set, cannot fake time" >&2
        exit 1
    fi
    FAKETIME="$(date -d @$timestamp '+%Y-%m-%d %H:%M:%S')" \
    LD_PRELOAD=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1 \
    "$@"
}