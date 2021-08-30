// const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers } = require("hardhat");
const config = require("config");

const chld_daiAddress = config.polygon.tokens.dai.address;
const chld_wethAddress = config.polygon.tokens.wEth.address;
const unitrollerAddress = config.polygon.compound.unitrollerAddress;
const crDaiAddress = config.polygon.tokens.crDai.address;
const crWethAddress = config.polygon.tokens.crWeth.address;
const ChildChainManager = config.polygon.admin.ChildChainManager;


const erc20Abi = require("./abis/UChild-abi.json");
const cErc20Abi = require("./abis/CErc20-delegator-abi.json");
const compAbi = require("./abis/comptroller-abi.json");

const provider = hre.ethers.provider;

const dai = env.polygon.tokens.dai.contract;
const crDai = env.polygon.tokens.crDai.contract;
const weth = env.polygon.tokens.wEth.contract;
const crWeth = env.polygon.tokens.crWeth.contract;
const comp = env.polygon.compound.contract;

const decimals = new Map();
async function setDecimals() {
  decimals.set("DAI", await dai.decimals());
  decimals.set("ETH", 18);
  decimals.set("WETH", await weth.decimals());
  decimals.set("crWETH", await crWeth.decimals());
  decimals.set("crDAI", await crDai.decimals());
}

function parseToken(amount, symbol) {
  return ethers.utils.parseUnits(amount, decimals.get(symbol));
}
function formatToken(amount, symbol) {
  return ethers.utils.formatUnits(amount, decimals.get(symbol));
}

it("should call basic contracts on polygon", async function () {
  await setDecimals();
  const [testSigner] = await ethers.getSigners();
  console.log(
    "testRunner ETH",
    formatToken(await testSigner.getBalance(), "ETH")
  );
  console.log(
    "testRunner DAI",
    formatToken(await dai.balanceOf(testSigner.address), "DAI")
  );

  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [env.polygon.admin.childChainManager],
  });
  const admin_signer = await provider.getSigner(
    env.polygon.admin.childChainManager
  );
  await hre.network.provider.send("hardhat_setBalance", [
    env.polygon.admin.childChainManager,
    ethers.utils.hexValue(parseToken("10", "ETH")),
  ]);
  //  const admin_role = await dai.DEFAULT_ADMIN_ROLE();
  //  console.log("admin role: ", await dai.getRoleMember("0x8f4f2da22e8ac8f11e15f9fc141cddbb5deea8800186560abb6e68c5496619a9",0));
  console.log(
    "manager ETH",
    formatToken(await admin_signer.getBalance(), "ETH")
  );
  //  console.log("manager DAI", formatToken(await dai.balanceOf(env.polygon.admin.childChainManager),'DAI'));
  const amount = ethers.utils.hexZeroPad(parseToken("1000", "DAI"), 32);
  console.log(amount);
  await dai.connect(admin_signer).deposit(testSigner.address, amount);
  console.log(
    "testRunner DAIs:",
    formatToken(await dai.balanceOf(testSigner.address), "DAI")
  );
});
