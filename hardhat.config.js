//usePlugin("@nomiclabs/buidler-truffle5");
process.env["NODE_CONFIG_DIR"] = __dirname + "/config/";
require("dotenv-flow").config(); // Reads local environment variables from .env*.local files
const config = require("config"); // Reads configuration files from /config/
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("adhusson-hardhat-solpp");
const test_solidity = require("./lib/test_solidity.js");

require("./lib/hardhat-ethereum-env.js"); // Adds Ethereum environment to Hardhat Runtime Envrionment
require("./lib/hardhat-polygon-env.js"); // Adds Polygon environment to Hardhat Runtime Envrionment
// FIXME the console approach is not working due to the spawning of a new process
//require("./lib/mangrove-console.js"); // Add auto-deploy of Mangrove to the Hardhat Console
//require("./lib/hardhat-mangrove.js");

// Special task for running Solidity tests
task(
  "test-solidity",
  "[Giry] Run tests of Solidity contracts with suffix _Test"
)
  .addFlag("noCompile", "Don't compile before running this task")
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
        noCompile: params.noCompile,
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

// Use Hardhat configuration from loaded configuration files
module.exports = config.hardhat;
