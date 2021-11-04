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
    mumbai: {
      gasPrice: 30 * 10 ** 9,
      gasMultiplier: 1,
      blockGasLimit: 12000000,
      url: process.env["MUMBAI_NODE_URL"],
      chainId: 80001,
      accounts: {
        mnemonic: process.env["MUMBAI_MNEMONIC"],
      },
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
    path: "./build/exported-abis",
    clear: true,
    flat: true,
    only: [
      ":Mangrove$",
      ":MgvEvents$",
      ":MgvReader$",
      ":MgvCleaner$",
      ":MgvOracle$",
      ":TestMaker$",
      ":TestTokenWithDecimals$",
      ":IERC20$",
    ],
    spacing: 2,
    pretty: false,
  },
  testSolidity: {
    logFormatters: require("lib/log_formatters"),
  },
  solpp: {
    defs: require("structs.js"),
  },
  // see github.com/wighawag/hardhat-deploy#1-namedaccounts-ability-to-name-addresses
  namedAccounts: {
    deployer: {
      default: 1, // take second account as deployer
    },
    maker: {
      default: 2,
    },
    cleaner: {
      default: 3,
    },
    gasUpdater: {
      default: 4,
    },
  },
  mocha: defer(function () {
    // Use same configuration when running Mocha via Hardhat
    return this.mocha;
  }),
};

module.exports = config;
