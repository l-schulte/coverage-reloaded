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
    # Use a RELATIVE offset (seconds from now), not an absolute "YYYY-MM-DD
    # hh:mm:ss" timestamp. An absolute FAKETIME FREEZES the clock, which makes
    # any code that waits on a realtime deadline (e.g. `while (Date.now() <
    # deadline)`) busy-loop forever at 100% CPU and hang the run. A relative
    # offset still makes the wall clock report the commit date while keeping it
    # advancing, so deadlines resolve and date-based snapshots still pass.
    # Format must be a bare signed integer (printf '%+d' yields "+N"/"-N"); a
    # leading "+-" is NOT parsed by libfaketime.
    local off=$(( timestamp - $(date +%s) ))
    FAKETIME="$(printf '%+d' "$off")" \
    LD_PRELOAD=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1 \
    "$@"
}