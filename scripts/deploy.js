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
  const Dex = await $e.getContractFactory("Dex", {
    libraries: { DexLib: dexLib.address },
  });
  const dex = await Dex.deploy(1, 1, 1, true);
  console.log("dex", dex);

  /* To activate for two tokens:
  const TestToken = await $e.getContractFactory("TestToken");
  const aToken = await TestToken.deploy(owner.address, "A", "$A");
  const bToken = await TestToken.deploy(owner.address, "B", "$B");
  console.log("aToken", aToken.address);
  console.log("bToken", bToken.address);

  dex.setActive(aToken.address, bToken.address, true);
  */
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
