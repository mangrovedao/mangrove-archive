// Config file for test environment
var config = {};

config.mocha = {
  reporter: "@espendk/json-file-reporter",
  reporterOptions: {
    output: "solidity-mocha-test-report.json",
  },
};

module.exports = config;
