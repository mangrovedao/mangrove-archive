// Config file for Solidity tests in test environment
// NB: We are abusing the NODE_APP_INSTANCE env var to make test suite specific configurations.
var config = {};

/////////////////////////
// Mocha configuration //
config.mocha = {
  reporter: "@espendk/json-file-reporter",
  reporterOptions: {
    output: "ethereum-mainnet-mocha-test-report.json",
  },
};

///////////////////////////
// Hardhat configuration //
config.hardhat = {
  networks: {
    hardhat: {
      forking: {
        url: process.env.ETHEREUM_NODE_URL,
        blockNumber: 12901866,
      },
    },
  },
};

module.exports = config;
