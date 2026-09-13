for (const method of ["log", "debug", "info", "warn"]) {
    console[method] = () => {};
}
