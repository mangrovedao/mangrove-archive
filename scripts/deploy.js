// Run with
//   npx hardhat run scripts/deploy.js
// possibly prefixed with
//   HARDHAT_NETWORK=<network name from hardhat.config>
// if you want the deploy to persist somewhere
async function main() {
  const $e = hre.ethers;

  const [owner, addr1, addr2] = await $e.getSigners();
  console.log("owner", owner.address);
  const DexLib = await $e.getContractFactory("DexLib");
  const dexLib = await DexLib.deploy();
  console.log("dexlib", dexLib.address);

  const TestToken = await $e.getContractFactory("TestToken");
  const aToken = await TestToken.deploy(owner.address, "A", "$A");
  const bToken = await TestToken.deploy(owner.address, "B", "$B");
  console.log("aToken", aToken.address);
  console.log("bToken", bToken.address);

  const Sauron = await $e.getContractFactory("Sauron");
  const sauron = await Sauron.deploy(1, 1, 1);
  console.log("sauron", sauron.address);

  const DexDeployer = await $e.getContractFactory("DexDeployer", {
    libraries: { DexLib: dexLib.address },
  });
  const dexDeployer = await DexDeployer.deploy(sauron.address);
  console.log("dexdeployer", dexDeployer.address);

  await dexDeployer.deploy(aToken.address, bToken.address, true);

  const dex = await dexDeployer.dexes(aToken.address, bToken.address);
  console.log("dex", dex);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
