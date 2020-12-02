// Run with
//   npx hardhat run scripts/deploy.js
// possibly prefixed with
//   HARDHAT_NETWORK=<network name from hardhat.config>
// if you want the deploy to persist somewhere
async function main() {
  const $e = hre.ethers;

  const [owner, addr1, addr2] = await $e.getSigners();
  console.log("owner is", owner);
  const DexLib = await $e.getContractFactory("DexLib");
  const dexLib = await DexLib.deploy();

  const TestToken = await $e.getContractFactory("TestToken");
  const aToken = await TestToken.deploy(owner.address, "A", "$A");
  const bToken = await TestToken.deploy(owner.address, "B", "$B");

  const DexDeployer = await $e.getContractFactory("DexDeployer", {
    libraries: { DexLib: dexLib.address },
  });
  const dexDeployer = await DexDeployer.deploy();

  await dexDeployer.deploy(1, 1, 1, 1, aToken.address, bToken.address, true);

  const dex = await dexDeployer.dexes(aToken.address, bToken.address);
  console.log("dex", dex);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
