// const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

// Address of Join (has auth) https://changelog.makerdao.com/ -> releases -> contract addresses -> MCD_JOIN_DAI
const ChildChainManager = "0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa"; // has depositor role in ChildERc20 contracts
const ChildChain = "0xD9c7C4ED4B66858301D0cb28Cc88bf655Fe34861";

const chld_daiAddress = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063";
const chld_cDaiAddress = "0x6fe9C1631b37a2b438CFD3d67409E15503Ddd535";
const chld_wethAddress = "0xAe740d42E4ff0C5086b2b5b5d149eB2F9e1A754F";
const chld_cWethAddress = "0x7ef18d0a9C3Fb1A716FF6c3ED0Edf52a2427F716";
const unitrollerAddress = "0x20CA53E2395FA571798623F1cFBD11Fe2C114c24";

const erc20Abi = require("./abis/UChild-abi.json");
const cErc20Abi = require("./abis/CErc20-delegator-abi.json");
const compAbi = require("./abis/comptroller-abi.json");

const provider = hre.ethers.provider;

const dai = new ethers.Contract(chld_daiAddress, erc20Abi, provider);
const crDai = new ethers.Contract(chld_cDaiAddress, cErc20Abi, provider);
const weth = new ethers.Contract(chld_wethAddress, erc20Abi, provider);
const crWeth = new ethers.Contract(chld_cWethAddress, cErc20Abi, provider);
const comp = new ethers.Contract(unitrollerAddress, compAbi, provider);

const decimals = new Map();
async function setDecimals() {
  decimals.set("DAI", await dai.decimals());
  decimals.set("ETH", 18);
  decimals.set("WETH", await weth.decimals());
  decimals.set("cETH", await crWeth.decimals());
  decimals.set("cDAI", await crDai.decimals());
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
    params: [ChildChainManager],
  });
  const admin_signer = await provider.getSigner(ChildChainManager);
  await hre.network.provider.send("hardhat_setBalance", [
    ChildChainManager,
    ethers.utils.hexValue(parseToken("10", "ETH")),
  ]);
  //  const admin_role = await dai.DEFAULT_ADMIN_ROLE();
  //  console.log("admin role: ", await dai.getRoleMember("0x8f4f2da22e8ac8f11e15f9fc141cddbb5deea8800186560abb6e68c5496619a9",0));
  console.log(
    "manager ETH",
    formatToken(await admin_signer.getBalance(), "ETH")
  );
  //  console.log("manager DAI", formatToken(await dai.balanceOf(ChildChainManager),'DAI'));
  const amount = ethers.utils.hexZeroPad(parseToken("1000", "DAI"), 32);
  console.log(amount);
  await dai.connect(admin_signer).deposit(testSigner.address, amount);
  console.log(
    "testRunner DAIs:",
    formatToken(await dai.balanceOf(testSigner.address), "DAI")
  );
});
