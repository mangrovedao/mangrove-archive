// Config file with defaults
var config = {};

var defer = require("config/defer").deferConfig;

///////////////////////////
// Hardhat configuration //
config.hardhat = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      gasPrice: 8000000000,
      gasMultiplier: 1,
      blockGasLimit: 7000000000,
      allowUnlimitedContractSize: true,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
    },
  },
  paths: {
    artifacts:
      "node_modules/@giry/mangrove-solidity/build/cache/solpp-generated-contracts",
  },
  external: {
    contracts: [
      {
        artifacts:
          "node_modules/@giry/mangrove-solidity/build/cache/solpp-generated-contracts",
        deploy: "node_modules/@giry/mangrove-solidity/deploy",
      },
    ],
    deployments: {
      localhost: "node_modules/@giry/mangrove-solidity/deployments",
    },
  },
  // see github.com/wighawag/hardhat-deploy#1-namedaccounts-ability-to-name-addresses
  namedAccounts: {
    deployer: {
      default: 0, // take first account as deployer
    },
  },
  mocha: defer(function () {
    // Use same configuration when running Mocha via Hardhat
    return this.mocha;
  }),
};

module.exports = config;