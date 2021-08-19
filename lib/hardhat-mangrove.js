extendEnvironment((hre) => {
  hre.mangrove = {
    deployOnEthereum: () => deployOnEthereum(hre),
    deployIfMissingOnEthereum: () => deployIfMissingOnEthereum(hre),
    activateMarketOnEthereum: (aTokenAddress, bTokenAddress) =>
      activateMarketOnEthereum(hre, aTokenAddress, bTokenAddress),
  };
});

async function deployIfMissingOnEthereum(hre) {
  if (!hre.env || !hre.env.ethereum || !hre.env.ethereum.mgv) {
    await deployOnEthereum(hre);
  }
}

async function deployOnEthereum(hre) {
  const Mangrove = await hre.ethers.getContractFactory("Mangrove");
  const mgv_gasprice = 500;
  let gasmax = 2000000;
  const mgv = await Mangrove.deploy(mgv_gasprice, gasmax);
  await mgv.deployed();
  const receipt = await mgv.deployTransaction.wait(0);
  // console.log("GasUsed during deploy: ", receipt.gasUsed.toString());
  if (!hre.env) {
    hre.env = {};
  }
  if (!hre.env.ethereum) {
    hre.env.ethereum = {};
  }
  hre.env.ethereum.mgv = { contract: mgv };
}

async function activateMarketOnEthereum(hre, aTokenAddress, bTokenAddress) {
  fee = 30; // setting fees to 0.03%
  density = 10000;
  overhead_gasbase = 20000;
  offer_gasbase = 20000;
  activateTx = await hre.env.ethereum.mgv.contract.activate(
    aTokenAddress,
    bTokenAddress,
    fee,
    density,
    overhead_gasbase,
    offer_gasbase
  );
  await activateTx.wait();
}
