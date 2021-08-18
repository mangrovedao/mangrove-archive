extendEnvironment((hre) => {
  hre.mangrove = {
    deployOnEthereum: () => deployMangroveOnEthereum(hre),
  };
});

async function deployMangrove(hre) {
  const Mangrove = await hre.ethers.getContractFactory("Mangrove");
  mgv_gasprice = 500;
  let gasmax = 2000000;
  mgv = await Mangrove.deploy(mgv_gasprice, gasmax);
  await mgv.deployed();
  receipt = await mgv.deployTransaction.wait(0);
  // console.log("GasUsed during deploy: ", receipt.gasUsed.toString());
  if (!hre.ethereum) {
    hre.ethereum = {};
  }
  hre.ethereum.mgv = { contract: mgv };

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
