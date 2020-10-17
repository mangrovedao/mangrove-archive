//usePlugin("@nomiclabs/buidler-truffle5");
usePlugin("@nomiclabs/buidler-ethers");
usePlugin("buidler-deploy");
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
  .setAction(async (params, bre) => {
    await test_solidity(
      {
        argTestContractNames: params.contracts || [],
        showEvents: params.showEvents,
      },
      bre
    );
  });

module.exports = {
  defaultNetwork: "buidlerevm",
  networks: {
    buidlerevm: {},
    localhost: {
      url: "http://127.0.0.1:8545",
    },
  },
  solc: {
    version: "0.7.2",
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
