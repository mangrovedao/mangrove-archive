// Config file for Polygon mainnet tests in test environment
// NB: We are abusing the NODE_APP_INSTANCE env var to make test suite specific configurations.
var config = {};

///////////////////////////
// Polygon configuration //
config.polygon = require("./polygon/polygon-mumbai.json");

/////////////////////////
// Mocha configuration //
config.mocha = {
  // Use multiple reporters to output to both stdout and a json file
  reporter: "mocha-multi-reporters",
  reporterOptions: {
    reporterEnabled: "spec, @espendk/json-file-reporter",
    espendkJsonFileReporterReporterOptions: {
      output: "polygon-mumbai-mocha-test-report.json",
    },
  },
};

///////////////////////////
// Hardhat configuration //
if (!process.env.MUMBAI_NODE_URL) {
  throw new Error("MUMBAI_NODE_URL must be set to test Polygon mainnet");
}
config.hardhat = {
  networks: {
    hardhat: {
      forking: {
        url: process.env.MUMBAI_NODE_URL,
        blockNumber: 20658175,
      },
    },
  },
};

module.exports = config;
