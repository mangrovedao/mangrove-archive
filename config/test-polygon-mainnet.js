// Config file for Ethereum mainnet tests in test environment
// NB: We are abusing the NODE_APP_INSTANCE env var to make test suite specific configurations.
var config = {};

/////////////////////////
// Mocha configuration //
config.mocha = {
  // Use multiple reporters to output to both stdout and a json file
  reporter: "mocha-multi-reporters",
  reporterOptions: {
    reporterEnabled: "spec, @espendk/json-file-reporter",
    espendkJsonFileReporterReporterOptions: {
      output: "polygon-mainnet-mocha-test-report.json",
    },
  },
};

///////////////////////////
// Hardhat configuration //
if (!process.env.POLYGON_NODE_URL) {
  throw new Error("POLYGON_NODE_URL must be set to test Polygon mainnet");
}
config.hardhat = {
  networks: {
    hardhat: {
      forking: {
        url: process.env.POLYGON_NODE_URL,
        blockNumber: 18552121,
      },
    },
  },
};

module.exports = config;
