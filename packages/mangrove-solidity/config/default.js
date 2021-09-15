// Config file with defaults
var config = {};

var defer = require("config/defer").deferConfig;

// TODO Find better way of doing this...
function requireFromProjectRoot(pathFromProjectRoot) {
  return require(__dirname + "/../" + pathFromProjectRoot);
}

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
    artifacts: "./build/cache/solpp-generated-contracts", // NB This path is a bit weird - can we remove the cache part?
  },
  abiExporter: {
    path: "./build/exported-abis", // NB I changed this, as we were generating files in one package into a different package
    clear: true,
    flat: false,
    only: [":MgvReader$", ":Mangrove$", ":MgvEvents$", ":IERC20$"],
    spacing: 2,
    pretty: false,
  },
  testSolidity: {
    logFormatters: requireFromProjectRoot("./lib/log_formatters"),
  },
  solpp: {
    defs: requireFromProjectRoot("./structs.js"),
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
