//usePlugin("@nomiclabs/buidler-truffle5");
require("@nomiclabs/hardhat-ethers");
require("hardhat-deploy");
const test_solidity = require("./lib/test_solidity.js");

// Special task for running Solidity tests
task(
  "test-solidity",
  "[Giry] Run tests of Solidity contracts with suffix _Test"
)
  .addFlag("showEvents", "Show all non-test events during tests")
  .addFlag("showTestEvents", "Show all test events during tests")
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
        showEvents: params.showEvents,
        showTestEvents: params.showTestEvents,
        prefix: params.prefix,
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
  logFormatters: {
    OBState: (log, rawLog, originator, formatArg) => {
      /* Reminder:

      event OBState(
      uint[] offerIds,
      uint[] wants,
      uint[] gives,
      address[] makerAddr
    );

      */

      const ob = log.args["offerIds"].map((id, i) => {
        return {
          id: formatArg(id),
          wants: formatArg(log.args.wants[i]),
          gives: formatArg(log.args.gives[i]),
          maker: formatArg(log.args.makerAddr[i], "address"),
        };
      });

      const lineA = ({id, wants, gives, maker}) => {
        const suffix = maker.length > 15 ? "..." : "";
        return `${id.padEnd(3)}: ${wants.padEnd(15)}${gives.padEnd(
          15
        )}${maker.slice(0, 20)}${suffix}`;
      };
      //const lineB = ({gas,gasprice});

      console.log(
        " " + lineA({id: "id", wants: "wants", gives: "gives", maker: "maker"})
      );
      console.log("├" + "─".repeat(3 + 2 + 15 + 15 + 15 + 3 - 2) + "┤");
      ob.forEach((o) => console.log(" " + lineA(o)));
      console.log("└" + "─".repeat(3 + 2 + 15 + 15 + 15 + 3 - 2) + "┘");
    },
  },
};
