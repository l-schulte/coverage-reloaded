// No-op replacement for buildRequests.js.
// Skips live API caching to avoid type mismatches between the committed
// cached data (regions.json, typesLegacy.json, kernels.json) and the live
// API response, which may contain fields not yet in the TypeScript types.
module.exports = async () => 0;
