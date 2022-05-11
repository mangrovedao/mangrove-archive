// Add Ethereum environment to Hardhat Runtime Environment
extendEnvironment((hre) => {
  hre.env = require("./netfork-env")(hre.ethers);
});
