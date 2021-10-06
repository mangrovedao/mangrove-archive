/**
 * @type import('hardhat/config').HardhatUserConfig
 */
config = require("./src/util/config").config; // FIXME This seems a bit iffy - do we want to use the same config structure for test configuration as for run-time configuration?
require("hardhat-deploy");
require("hardhat-deploy-ethers");

module.exports = config.hardhat;
