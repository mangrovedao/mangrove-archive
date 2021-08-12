// Config file for test environment
var config = {};

/////////////////////////
// Mocha configuration //
config.mocha = {
  reporter: "@espendk/json-file-reporter",
  reporterOptions: {
    output: "solidity-mocha-test-report.json",
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
