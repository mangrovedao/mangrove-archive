//usePlugin("@nomiclabs/buidler-truffle5");
require("@nomiclabs/hardhat-ethers");
require("hardhat-deploy");
const test_solidity = require("./lib/test_solidity.js");

// Special task for running Solidity tests
task(
  "test-solidity",
  "[Giry] Run tests of Solidity contracts with suffix _Test"
)
  .addFlag("showEvents", "Show all solidity events during tests")
  .addOptionalVariadicPositionalParam(
    "contracts",
    "Which contracts to test (default:all)"
  )
  .setAction(async (params, hre) => {
    await test_solidity(
      {
        argTestContractNames: params.contracts || [],
        showEvents: params.showEvents,
      },
      hre
    );
  });

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {blockGasLimit: 7000000000},
    localhost: {
      url: "http://127.0.0.1:8545",
    },
  },
  solidity: {
    version: "0.7.4",
    optimizer: {
      enabled: false,
      runs: 200,
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./build",
  },
};