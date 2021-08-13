// Config file for Solidity tests in test environment
// NB: We are abusing the NODE_APP_INSTANCE env var to make test suite specific configurations.
var config = {};

/////////////////////////
// Mocha configuration //
config.mocha = {
  reporter: "@espendk/json-file-reporter",
  reporterOptions: {
    output: "solidity-mocha-test-report.json",
  },
};

module.exports = config;
