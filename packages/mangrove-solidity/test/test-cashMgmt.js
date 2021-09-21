const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers, env, mangrove, network } = require("hardhat");

const provider = ethers.provider;
const lc = require("../lib/libcommon.js");

async function deployStrat(strategy, mgv) {
  const dai = await lc.getContract("DAI");
  const wEth = await await lc.getContract("WETH");
  const comp = await lc.getContract("COMP");
  const aave = await lc.getContract("AAVE"); //returns addressesProvider
  const cwEth = await lc.getContract("CWETH");
  const cDai = await lc.getContract("CDAI");
  const Strat = await ethers.getContractFactory(strategy);
  let makerContract = null;
  let market = [null, null]; // market pair for lender
  let enterMarkets = true;
  switch (strategy) {
    case "SimpleCompoundRetail":
    case "AdvancedCompoundRetail":
      makerContract = await Strat.deploy(
        comp.address,
        mgv.address,
        wEth.address
      );
      market = [cwEth.address, cDai.address];
      break;
    case "SimpleAaveRetail":
    case "AdvancedAaveRetail":
      makerContract = await Strat.deploy(aave.address, mgv.address);
      market = [wEth.address, dai.address];
      // aave rejects market entering if underlying balance is 0 (will self enter at first deposit)
      enterMarkets = false;
      break;
    default:
      console.warn("Undefined strategy " + strategy);
  }
  await makerContract.deployed();

  // provisioning Mangrove on behalf of MakerContract
  let overrides = { value: lc.parseToken("2.0", 18) };
  tx = await mgv["fund(address)"](makerContract.address, overrides);
  await tx.wait();

  lc.assertEqualBN(
    await mgv.balanceOf(makerContract.address),
    lc.parseToken("2.0", 18),
    "Failed to fund the Mangrove"
  );

  // testSigner approves Mangrove for WETH/DAI before trying to take offers
  tkrTx = await wEth
    .connect(testSigner)
    .approve(mgv.address, ethers.constants.MaxUint256);
  await tkrTx.wait();
  // taker approves mgv for DAI erc
  tkrTx = await dai
    .connect(testSigner)
    .approve(mgv.address, ethers.constants.MaxUint256);
  await tkrTx.wait();

  allowed = await wEth.allowance(testSigner.address, mgv.address);
  lc.assertEqualBN(allowed, ethers.constants.MaxUint256, "Approve failed");

  /*********************** MAKER SIDE PREMICES **************************/
  let mkrTxs = [];
  let i = 0;
  // offer should get/put base/quote tokens on lender contract (OK since `testSigner` is MakerContract admin)
  if (enterMarkets) {
    mkrTxs[i++] = await makerContract.connect(testSigner).enterMarkets(market);
  }
  // testSigner asks MakerContract to approve Mangrove for base (DAI/WETH)
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .approveMangrove(dai.address, ethers.constants.MaxUint256);
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .approveMangrove(wEth.address, ethers.constants.MaxUint256);
  // One sends 1000 DAI to MakerContract
  mkrTxs[i++] = await dai
    .connect(testSigner)
    .transfer(
      makerContract.address,
      lc.parseToken("1000.0", await lc.getDecimals("DAI"))
    );
  // testSigner asks makerContract to approve lender to be able to mint [c/a]Token
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .approveLender(market[0], ethers.constants.MaxUint256);
  // NB in the special case of cEth this is only necessary to repay debt
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .approveLender(market[1], ethers.constants.MaxUint256);
  // makerContract deposits some DAI on Lender (remains 100 DAIs on the contract)
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .mint(market[1], lc.parseToken("900.0", await lc.getDecimals("DAI")));

  await lc.synch(mkrTxs);
  /***********************************************************************/
  return makerContract;
}

async function execLenderStrat(makerContract, mgv, lenderName) {
  const dai = await lc.getContract("DAI");
  const wEth = await await lc.getContract("WETH");

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);

  // // posting new offer on Mangrove via the MakerContract `post` method
  let offerId = await lc.newOffer(
    makerContract,
    "DAI",
    "WETH",
    lc.parseToken("1000.0", await lc.getDecimals("DAI")), // promised DAI
    lc.parseToken("0.5", await lc.getDecimals("WETH")) // required WETH
  );

  [offer] = await mgv.offerInfo(dai.address, wEth.address, offerId);
  lc.assertEqualBN(
    offer.gives,
    lc.parseToken("1000.0", await lc.getDecimals("DAI")),
    "Offer not correctly inserted"
  );

  // following snipe will repay WETH debt while creating a small one in DAI
  // For compound taker need to approve cEth for this
  let [takerGot, takerGave] = await lc.snipe(
    mgv,
    "DAI", // maker base
    "WETH", // maker quote
    offerId,
    lc.parseToken("800.0", await lc.getDecimals("DAI")), // taker wants 0.8 DAI
    lc.parseToken("0.5", await lc.getDecimals("WETH")) // taker is ready to give up-to 0.5 WETH
  );

  lc.assertEqualBN(
    takerGot,
    lc.netOf(lc.parseToken("800.0", await lc.getDecimals("DAI")), fee),
    "Incorrect received amount"
  );

  lc.assertEqualBN(
    takerGave,
    lc.parseToken("0.4", await lc.getDecimals("WETH")),
    "Incorrect given amount"
  );

  // checking that MakerContract did put WETH on lender --allowing 5 gwei of rounding error
  await lc.expectAmountOnLender(makerContract, lenderName, [
    ["DAI", lc.parseToken("200", await lc.getDecimals("DAI")), 4],
    ["WETH", takerGave, 8],
  ]);
  await lc.logLenderStatus(makerContract, lenderName, ["WETH", "DAI"]);
}

async function execTraderStrat(makerContract, mgv, lenderName) {
  const dai = await lc.getContract("DAI");
  const wEth = await await lc.getContract("WETH");

  await lc.logLenderStatus(makerContract, lenderName, ["WETH", "DAI"]);

  // // posting new offer on Mangrove via the MakerContract `post` method
  let offerId = await lc.newOffer(
    makerContract,
    "DAI",
    "WETH",
    lc.parseToken("300.0", await lc.getDecimals("DAI")), // promised DAI (will need to borrow)
    lc.parseToken("0.15", await lc.getDecimals("WETH")) // required WETH
  );

  let [offer] = await mgv.offerInfo(dai.address, wEth.address, offerId);

  lc.assertEqualBN(
    offer.gives,
    lc.parseToken("300.0", await lc.getDecimals("DAI")),
    "Offer not correctly inserted"
  );

  let [takerGot, takerGave] = await lc.snipe(
    mgv,
    "DAI", // maker base
    "WETH", // maker quote
    offerId,
    lc.parseToken("300", await lc.getDecimals("DAI")),
    lc.parseToken("0.15", await lc.getDecimals("WETH"))
  );
  lc.assertEqualBN(
    takerGot,
    lc.netOf(lc.parseToken("300.0", await lc.getDecimals("DAI")), fee),
    "Incorrect received amount"
  );
  lc.assertEqualBN(
    takerGave,
    lc.parseToken("0.15", await lc.getDecimals("WETH")),
    "Incorrect given amount"
  );
  await lc.expectAmountOnLender(makerContract, lenderName, [
    ["DAI", lc.parseToken("700", await lc.getDecimals("DAI")), 4],
    ["WETH", takerGave, 8],
  ]);

  await lc.logLenderStatus(makerContract, lenderName, ["WETH", "DAI"]);

  // testSigner asks MakerContract to approve Mangrove for base (weth)
  mkrTx2 = await makerContract
    .connect(testSigner)
    .approveMangrove(wEth.address, ethers.constants.MaxUint256);
  await mkrTx2.wait();

  offerId = await lc.newOffer(
    makerContract,
    "WETH",
    "DAI",
    lc.parseToken("0.2", await lc.getDecimals("WETH")), // promised WETH
    lc.parseToken("380.0", await lc.getDecimals("DAI")) // required DAI
  );

  [takerGot, takerGave] = await lc.snipe(
    mgv,
    "WETH",
    "DAI",
    offerId,
    lc.parseToken("0.2", await lc.getDecimals("WETH")), // wanted WETH
    lc.parseToken("380.0", await lc.getDecimals("DAI")) // giving DAI
  );

  lc.assertEqualBN(
    takerGot,
    lc.netOf(lc.parseToken("0.2", await lc.getDecimals("WETH")), fee),
    "Incorrect received amount"
  );
  lc.assertEqualBN(
    takerGave,
    lc.parseToken("380", await lc.getDecimals("DAI")),
    "Incorrect given amount"
  );

  await lc.logLenderStatus(makerContract, lenderName, ["WETH", "DAI"]);

  offerId = await lc.newOffer(
    makerContract,
    "DAI",
    "WETH",
    lc.parseToken("1500", await lc.getDecimals("DAI")), // promised DAI
    lc.parseToken("0.63", await lc.getDecimals("WETH")) // required WETH
  );
  [takerGot, takerGave] = await lc.snipe(
    mgv,
    "DAI",
    "WETH",
    offerId,
    lc.parseToken("1500", await lc.getDecimals("DAI")), // wanted DAI
    lc.parseToken("0.63", await lc.getDecimals("WETH")) // giving WETH
  );
  lc.assertEqualBN(
    takerGot,
    lc.netOf(lc.parseToken("1500", await lc.getDecimals("DAI")), fee),
    "Incorrect received amount"
  );
  lc.assertEqualBN(
    takerGave,
    lc.parseToken("0.63", await lc.getDecimals("WETH")),
    "Incorrect given amount"
  );
  await lc.logLenderStatus(makerContract, lenderName, ["WETH", "DAI"]);
}

describe("Deploy strategies", function () {
  this.timeout(100_000); // Deployment is slow so timeout is increased
  testSigner = null;
  testRunner = null;
  mgv = null;

  before(async function () {
    // 1. mint (1000 dai, 1000 eth, 1000 weth) for testSigner
    // 2. activates (dai,weth) market
    const dai = await lc.getContract("DAI");
    const wEth = await await lc.getContract("WETH");

    [testSigner] = await ethers.getSigners();
    testRunner = testSigner.address;
    await lc.fund([
      ["ETH", "1000.0", testRunner],
      ["WETH", "10.0", testRunner],
      ["DAI", "10000.0", testRunner],
    ]);

    const daiBal = await dai.balanceOf(testRunner);
    const wethBal = await wEth.balanceOf(testRunner);

    lc.assertEqualBN(
      daiBal,
      lc.parseToken("10000.0", await lc.getDecimals("DAI"))
    );
    lc.assertEqualBN(
      wethBal,
      lc.parseToken("10.0", await lc.getDecimals("WETH")),
      "Minting WETH failed"
    );

    mgv = await lc.deployMangrove();
    await lc.activateMarket(mgv, dai.address, wEth.address);
    let cfg = await mgv.config(dai.address, wEth.address);
    assert(cfg.local.active, "Market is inactive");
  });

  it("Pure lender strat on compound", async function () {
    const makerContract = await deployStrat("SimpleCompoundRetail", mgv);
    await execLenderStrat(makerContract, mgv, "compound");
  });

  it("Lender/borrower strat on compound", async function () {
    const makerContract = await deployStrat("AdvancedCompoundRetail", mgv);
    await execTraderStrat(makerContract, mgv, "compound");
  });

  it("Pure lender strat on aave", async function () {
    const makerContract = await deployStrat("SimpleAaveRetail", mgv);
    await execLenderStrat(makerContract, mgv, "aave");
  });

  it("Lender/borrower strat on aave", async function () {
    const makerContract = await deployStrat("AdvancedAaveRetail", mgv);
    await execTraderStrat(makerContract, mgv, "aave");
  });
});
