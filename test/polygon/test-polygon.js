const { ethers, env, mangrove, network } = require("hardhat");

const lc = require("../libcommon");

const provider = hre.ethers.provider;

it("should call basic contracts on polygon", async function () {
  await lc.setDecimals();
  const [testSigner] = await ethers.getSigners();
  console.log(
    "testRunner ETH",
    lc.formatToken(await testSigner.getBalance(), "ETH")
  );
  console.log(
    "testRunner DAI",
    lc.formatToken(await lc.dai.balanceOf(testSigner.address), "DAI")
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
    ethers.utils.hexValue(lc.parseToken("10", "ETH")),
  ]);
  //  const admin_role = await dai.DEFAULT_ADMIN_ROLE();
  //  console.log("admin role: ", await dai.getRoleMember("0x8f4f2da22e8ac8f11e15f9fc141cddbb5deea8800186560abb6e68c5496619a9",0));
  console.log(
    "manager ETH",
    lc.formatToken(await admin_signer.getBalance(), "ETH")
  );
  //  console.log("manager DAI", formatToken(await dai.balanceOf(env.polygon.admin.childChainManager),'DAI'));
  const amount = ethers.utils.hexZeroPad(lc.parseToken("1000", "DAI"), 32);
  console.log(amount);
  await lc.dai.connect(admin_signer).deposit(testSigner.address, amount);
  console.log(
    "testRunner DAIs:",
    lc.formatToken(await lc.dai.balanceOf(testSigner.address), "DAI")
  );
});
