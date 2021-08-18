// Load console
task(
  "console",
  "Opens a hardhat console with MGV contracts deployed & loaded",
  async (args, hre, runSuper) => {
    console.log("Launching Hardhat Console with Mangrove environment");
    // FIXME changes to hre here does not affect the console as it runs a new process with a fresh hre...
    // Deploy MGV if not already available
    if (!hre.ethereum) {
      hre.ethereum = {};
    }
    // FIXME Auto-deploy should probably be disabled by default
    if (!hre.ethereum.mgv) {
      const mangroveContract = await deployMangrove(hre);
      hre.ethereum.mgv = { contract: mangroveContract };
    }
    return runSuper();
  }
);

async function deployMangrove(hre) {
  const Mangrove = await hre.ethers.getContractFactory("Mangrove");
  mgv_gasprice = 500;
  let gasmax = 2000000;
  mgv = await Mangrove.deploy(mgv_gasprice, gasmax);
  await mgv.deployed();
  receipt = await mgv.deployTransaction.wait(0);
  // console.log("GasUsed during deploy: ", receipt.gasUsed.toString());
  return {
    contract: mgv,
  };

  // // TODO only activate markets for tokens that have been configured
  // // TODO maybe don't activate markets automatically?
  // //activating (dai,weth) market
  // fee = 30; // setting fees to 0.03%
  // density = 10000;
  // overhead_gasbase = 20000;
  // offer_gasbase = 20000;
  // activateTx = await mgv.activate(
  //   hre.ethereum.tokens.dai.contract.address,
  //   hre.ethereum.tokens.wEth.contract.address,
  //   fee,
  //   density,
  //   overhead_gasbase,
  //   offer_gasbase
  // );
  // await activateTx.wait();

  // // //activating (weth,dai) market
  // fee = 30; // setting fees to 0.03%
  // density = 10000;
  // overhead_gasbase = 20000;
  // offer_gasbase = 20000;
  // activateTx = await mgv.activate(
  //   hre.ethereum.tokens.wEth.contract.address,
  //   hre.ethereum.tokens.dai.contract.address,
  //   fee,
  //   density,
  //   overhead_gasbase,
  //   offer_gasbase
  // );
  // await activateTx.wait();
  // return mgv;
}
