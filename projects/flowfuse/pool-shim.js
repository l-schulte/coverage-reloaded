'use strict';

const Module = require('module');
const origLoad = Module._load;

Module._load = function (request, parent, isMain) {
  const mod = origLoad.apply(this, arguments);
  if (request === 'sequelize' && mod && typeof mod === 'object') {
    const Sequelize = mod.Sequelize || (mod.default && mod.default.Sequelize) || mod.default;
    if (Sequelize && Sequelize.prototype && !Sequelize.__poolShimPatched) {
      const OrigSequelize = Sequelize;
      function PoolPatchedSequelize (...args) {
        const opts = args[args.length - 1];
        if (opts && typeof opts === 'object' && opts.storage === ':memory:') {
          opts.pool = Object.assign({}, opts.pool, { max: 1, min: 1 });
        }
        return OrigSequelize.apply(this, args);
      }
      PoolPatchedSequelize.prototype = OrigSequelize.prototype;
      Object.setPrototypeOf(PoolPatchedSequelize, OrigSequelize);
      Object.assign(PoolPatchedSequelize, OrigSequelize);
      PoolPatchedSequelize.__poolShimPatched = true;
      if (mod.Sequelize) mod.Sequelize = PoolPatchedSequelize;
      if (mod.default && mod.default.Sequelize) mod.default.Sequelize = PoolPatchedSequelize;
      if (mod.default === Sequelize) mod.default = PoolPatchedSequelize;
    }
  }
  return mod;
};
