const childProcess = require("child_process");
const originalSpawn = childProcess.spawn;

childProcess.spawn = function (command, args, options) {
    if (options && options.env) {
        options.env.BROWSERSLIST_IGNORE_OLD_DATA = "1";
    }
    return originalSpawn.call(this, command, args, options);
};
