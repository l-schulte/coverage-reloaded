// Fake Date for Node.js processes only.
// Usage: node -r /coverage_reloaded/fake-time-node.js ...
// The timestamp is read from the TIMESTAMP_EPOCH environment variable.
// This patches Date, Date.now(), and Date.parse to return commit-relative times.

const epoch = process.env.TIMESTAMP_EPOCH
    ? parseInt(process.env.TIMESTAMP_EPOCH, 10) * 1000
    : null;

if (epoch !== null && !isNaN(epoch)) {
    const delta = epoch - Date.now();

    const OrigDate = Date;

    // Patch Date constructor
    function PatchedDate(...args) {
        if (args.length === 0) {
            return new OrigDate(OrigDate.now() + delta);
        }
        if (args.length === 1 && typeof args[0] === 'string') {
            return new OrigDate(args[0]);
        }
        return new OrigDate(...args);
    }
    PatchedDate.prototype = OrigDate.prototype;
    PatchedDate.now = function now() {
        return OrigDate.now() + delta;
    };
    PatchedDate.parse = OrigDate.parse;
    PatchedDate.UTC = OrigDate.UTC;

    global.Date = PatchedDate;

    // Also patch performance.now if available (used by some test runners)
    if (typeof performance !== 'undefined' && performance.now) {
        const origPerfNow = performance.now.bind(performance);
        const perfDelta = delta;
        performance.now = function () {
            return origPerfNow() + perfDelta;
        };
    }
}
