// Config file with defaults
var config = {};

var defer = require("config/defer").deferConfig;

// TODO Find better way of doing this...
function requireFromProjectRoot(pathFromProjectRoot) {
  return require("./../" + pathFromProjectRoot);
}

config.ethereum = require("./ethereum/ethereum-mainnet.json");
config.polygon = require("./polygon/polygon-mainnet.json");

///////////////////////////
// Hardhat configuration //
const hardhat_networks = {
  hardhat: {
    gasPrice: 8000000000,
    gasMultiplier: 1,
    blockGasLimit: 7000000000,
    allowUnlimitedContractSize: true,
  },
  localhost: {
    url: "http://127.0.0.1:8545",
  },
};

if (process.env.ETHEREUM_NODE_URL) {
  hardhat_networks.ethereum = {
    url: process.env.ETHEREUM_NODE_URL, // ethereum node
    // blockNumber: 12901866,
  };
}

if (process.env.POLYGON_NODE_URL) {
  hardhat_networks.polygon = {
    url: process.env.POLYGON_NODE_URL,
    // blockNumber: 17284000, // block mined 26/07/2021
  };
}

config.hardhat = {
  defaultNetwork: "hardhat",
  networks: hardhat_networks,
  solidity: {
    version: "0.7.6",
    settings: {
      optimizer: {
        enabled: true,
        runs: 20000,
      },
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./build",
  },
  solpp: {
    defs: requireFromProjectRoot("./structs.js"),
  },
  mocha: defer(function () {
    // Use same configuration when running Mocha via Hardhat
    return this.mocha;
  }),
};

module.exports = config;
