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

require("./lib/hardhat-ethereum-env.js"); // Adds Ethereum environment to Hardhat Runtime Envrionment
require("./lib/hardhat-polygon-env.js"); // Adds Polygon environment to Hardhat Runtime Envrionment

require("@giry/hardhat-test-solidity");
// Use Hardhat configuration from loaded configuration files
module.exports = config.hardhat;
