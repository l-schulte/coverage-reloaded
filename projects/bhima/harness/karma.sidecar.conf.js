module.exports = function(config) {
  const projectConf = require('/coverage_reloaded/repo/karma.conf.js');
  projectConf(config);

  const sourceFiles = [
    { pattern: 'client/src/js/define.js', watched: false },
    { pattern: 'client/src/js/app.js', watched: false },
    { pattern: 'client/src/**/*.js', watched: false },
  ];

  const originalFiles = config.files.filter(f => {
    const pattern = typeof f === 'string' ? f : f.pattern;
    return !pattern.includes('bhima.min.js') && !pattern.includes('bhima.concat.js');
  });

  const specIndex = originalFiles.findIndex(f => {
    const pattern = typeof f === 'string' ? f : f.pattern;
    return pattern.includes('.spec.js');
  });

  const files = [
    ...originalFiles.slice(0, specIndex),
    ...sourceFiles,
    ...originalFiles.slice(specIndex),
  ];

  config.set({
    basePath: '/coverage_reloaded/repo',
    files,
    preprocessors: {
      ...(config.preprocessors || {}),
      'client/src/js/**/*.js': ['babel', 'coverage'],
      'client/src/modules/**/*.js': ['babel', 'coverage'],
      'client/src/components/**/*.js': ['babel', 'coverage'],
    },
    babelPreprocessor: {
      options: {
        configFile: '/coverage_reloaded/harness/babel.config.json',
        sourceMap: 'inline',
      },
    },
    reporters: [...(config.reporters || []), 'coverage'],
    coverageReporter: {
      type: 'lcovonly',
      dir: '/coverage_reloaded/harness/output',
      subdir: '.',
      file: 'lcov.info',
    },
    plugins: [
      ...(config.plugins || ['karma-*']),
      'karma-coverage',
      'karma-babel-preprocessor',
    ],
    browsers: ['ChromeHeadlessNoSandbox'],
    customLaunchers: {
      ChromeHeadlessNoSandbox: {
        base: 'ChromeHeadless',
        flags: ['--no-sandbox', '--disable-setuid-sandbox'],
      },
    },
    browserNoActivityTimeout: 120000,
    singleRun: true,
    client: {
      mocha: { bail: false },
    },
  });
};