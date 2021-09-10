//usePlugin("@nomiclabs/buidler-truffle5");
require("dotenv-flow").config(); // Reads local environment variables from .env*.local files
if (!process.env["NODE_CONFIG_DIR"]) {
    process.env["NODE_CONFIG_DIR"] = __dirname + "/config/";
}
const config = require("config"); // Reads configuration files from /config/
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-abi-exporter");
require("adhusson-hardhat-solpp");

require("./lib/hardhat-mainnet-env.js"); // Adds [Ethereum|polygon] mainnet environment to Hardhat Runtime Envrionment
// FIXME the console approach is not working due to the spawning of a new process
//require("./lib/mangrove-console.js"); // Add auto-deploy of Mangrove to the Hardhat Console
//require("./lib/hardhat-mangrove.js");

require("@giry/hardhat-test-solidity");
// Use Hardhat configuration from loaded configuration files
module.exports = config.hardhat;
