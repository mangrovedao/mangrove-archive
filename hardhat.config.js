//usePlugin("@nomiclabs/buidler-truffle5");
require("dotenv-flow").config(); // Reads local environment variables from .env*.local files
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("adhusson-hardhat-solpp");
const test_solidity = require("./lib/test_solidity.js");

// Special task for running Solidity tests
task(
  "test-solidity",
  "[Giry] Run tests of Solidity contracts with suffix _Test"
)
  .addFlag("showEvents", "Show all non-test events during tests")
  .addFlag("showTestEvents", "Show all test events during tests")
  .addFlag(
    "showTx",
    "Show all transaction hashes (disables revert between tests)"
  )
  .addFlag("showGas", "Show gas used for each test")
  .addFlag(
    "details",
    "Log events interpreted by the logFormatters hardhat.config parameter for additional details on the tests"
  )
  .addOptionalParam(
    "prefix",
    "Match test function names for prefix. Javascript regex. Remember to escape backslash and surround with single quotes if necessary.",
    ".*",
    types.string
  )
  .addOptionalVariadicPositionalParam(
    "contracts",
    "Which contracts to test (default:all)"
  )
  .setAction(async (params, hre) => {
    await test_solidity(
      {
        argTestContractNames: params.contracts || [],
        details: params.details,
        showGas: params.showGas,
        showTx: params.showTx,
        showEvents: params.showEvents,
        showTestEvents: params.showTestEvents,
        prefix: params.prefix,
      },
      hre
    );
  });

const networks = {
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
  networks.ethereum = {
    url: process.env.ETHEREUM_NODE_URL, // ethereum node
    // blockNumber: 12901866,
  };
}

if (process.env.POLYGON_NODE_URL) {
  networks.polygon = {
    url: process.env.POLYGON_NODE_URL,
    // blockNumber: 17284000, // block mined 26/07/2021
  };
}

module.exports = {
  defaultNetwork: "hardhat",
  networks: networks,
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
    defs: require("./structs.js"),
  },
};
