require("dotenv-flow").config(); // Reads local environment variables from .env*.local files
if (!process.env["NODE_CONFIG_DIR"]) {
  process.env["NODE_CONFIG_DIR"] = __dirname + "/config/";
}
const config = require("config"); // Reads configuration files from ./config/
require("hardhat-deploy");
require("hardhat-deploy-ethers");

// Use Hardhat configuration from loaded configuration files
module.exports = config.hardhat;
