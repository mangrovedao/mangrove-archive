const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers, env, mangrove, network } = require("hardhat");
const lc = require("lib/libcommon.js");
const chalk = require("chalk");

let testSigner = null;
const zero = lc.parseToken("0.0", 18);

async function deployStrat(strategy, mgv) {
  const dai = await lc.getContract("DAI");
  const wEth = await lc.getContract("WETH");
  const comp = await lc.getContract("COMP");
  const aave = await lc.getContract("AAVE"); //returns addressesProvider
  const cwEth = await lc.getContract("CWETH");
  const cDai = await lc.getContract("CDAI");
  const Strat = await ethers.getContractFactory(strategy);
  let makerContract = null;
  let market = [null, null]; // market pair for lender
  let oracle = null;
  let enterMarkets = true;
  switch (strategy) {
    case "SimpleCompoundRetail":
    case "AdvancedCompoundRetail":
    case "SwingingMarketMaker":
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
    case "PriceFed":
      SimpleOracle = await ethers.getContractFactory("SimpleOracle");
      oracle = await SimpleOracle.deploy();
      await oracle.deployed();
      makerContract = await Strat.deploy(
        oracle.address,
        aave.address,
        mgv.address
      );
      market = [wEth.address, dai.address];
      // aave rejects market entering if underlying balance is 0 (will self enter at first deposit)
      enterMarkets = false;
      await makerContract.setSlippage(300); // 3% slippage allowed
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
  if (oracle) {
    await oracle.setReader(makerContract.address); // maker Contract is the only one to be able to read data from oracle
    try {
      const oracleTx = await oracle.getPrice(dai.address); // should fail
      assert(false, "Reading price should have failed");
    } catch {
      await oracle.setPrice(dai.address, lc.parseToken("1.0", 6)); // sets DAI price to 1 USD (6 decimals)
      await oracle.setPrice(wEth.address, lc.parseToken("3000.0", 6)); // sets ETH price to 3K USD (6 decimals)
      makerContract.oracle = oracle;
    }
  }
  return makerContract;
}

async function execSwingerStrat(makerContract, mgv, lenderName) {
  const dai = await lc.getContract("DAI");
  const wEth = await lc.getContract("WETH");

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);
  await makerContract.setPrice(
    dai.address,
    wEth.address,
    lc.parseToken("3000.0", 18)
  );
  await makerContract.setPrice(
    wEth.address,
    dai.address,
    lc.parseToken("0.000334", 18)
  );

  await makerContract.startStrat(
    dai.address,
    wEth.address,
    lc.parseToken("1000.0", 18)
  );

  let book01 = await mgv.reader.book(dai.address, wEth.address, 0, 1);
  let book10 = await mgv.reader.book(wEth.address, dai.address, 0, 1);
  await lc.logOrderBook(book01, dai, wEth);
  await lc.logOrderBook(book10, wEth, dai);

  // market order
  await lc.marketOrder(
    mgv,
    "DAI",
    "WETH",
    lc.parseToken("1000", 18),
    lc.parseToken("0.34", 18)
  );
  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);

  book01 = await mgv.reader.book(dai.address, wEth.address, 0, 1);
  book10 = await mgv.reader.book(wEth.address, dai.address, 0, 1);
  await lc.logOrderBook(book01, dai, wEth);
  await lc.logOrderBook(book10, wEth, dai);

  // market order
  await lc.marketOrder(
    mgv,
    "WETH",
    "DAI",
    lc.parseToken("0.334", 18),
    lc.parseToken("1100", 18)
  );
  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);

  book01 = await mgv.reader.book(dai.address, wEth.address, 0, 1);
  book10 = await mgv.reader.book(wEth.address, dai.address, 0, 1);
  await lc.logOrderBook(book01, dai, wEth);
  await lc.logOrderBook(book10, wEth, dai);
}

async function execLenderStrat(makerContract, mgv, lenderName) {
  const dai = await lc.getContract("DAI");
  const wEth = await lc.getContract("WETH");

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);

  // // posting new offer on Mangrove via the MakerContract `newOffer` external function
  let offerId = await lc.newOffer(
    mgv,
    makerContract,
    "DAI", // base
    "WETH", // quote
    lc.parseToken("0.5", await lc.getDecimals("WETH")), // required WETH
    lc.parseToken("1000.0", await lc.getDecimals("DAI")) // promised DAI
  );

  let [takerGot, takerGave] = await lc.snipeSuccess(
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
    ["DAI", lc.parseToken("200", await lc.getDecimals("DAI")), zero, 4],
    ["WETH", takerGave, zero, 8],
  ]);
  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);
}

async function execPriceFedStrat(makerContract, mgv, lenderName) {
  const dai = await lc.getContract("DAI");
  const wEth = await lc.getContract("WETH");

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);

  // // posting new offer on Mangrove via the MakerContract `post` method
  let offerId = await lc.newOffer(
    mgv,
    makerContract,
    "DAI", //base
    "WETH", //quote
    lc.parseToken("0.2", await lc.getDecimals("WETH")), // required WETH
    lc.parseToken("1000.0", await lc.getDecimals("DAI")) // promised DAI
  );
  const filter_slippage = makerContract.filters.Slippage();
  makerContract.once(filter_slippage, (id, old_wants, new_wants, event) => {
    assert(
      id.eq(offerId),
      `Reneging on wrong offer Id (${id} \u2260 ${offerId})`
    );
    lc.assertEqualBN(old_wants, lc.parseToken("0.2", 18), "Invalid old price");
    assert(old_wants.lt(new_wants), "Invalid new price");
    console.log(
      "    " +
        chalk.green(`\u2713`) +
        chalk.grey(` Verified logged event `) +
        chalk.yellow(`(${event.event})`)
    );
    console.log();
  });

  // snipe should fail because offer will renege trade (price too low)
  await lc.snipeFail(
    mgv,
    "DAI", // maker base
    "WETH", // maker quote
    offerId,
    lc.parseToken("1000.0", await lc.getDecimals("DAI")), // taker wants 1000 DAI
    lc.parseToken("0.2", await lc.getDecimals("WETH")) // but 0.2. is not market price (should be >= 0,3334)
  );

  // new offer should have been put on the book with the correct price (same offer ID)
  let [takerGot, takerGave] = await lc.snipeSuccess(
    mgv,
    "DAI", // maker base
    "WETH", // maker quote
    offerId,
    lc.parseToken("1000.0", await lc.getDecimals("DAI")),
    lc.parseToken("0.3334", await lc.getDecimals("WETH"))
  );

  lc.assertEqualBN(
    takerGot,
    lc.netOf(lc.parseToken("1000.0", await lc.getDecimals("DAI")), fee),
    "Incorrect received amount"
  );

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);
  await lc.expectAmountOnLender(makerContract, lenderName, [
    ["DAI", zero, zero, 4], // no DAI remaining
    ["WETH", takerGave, zero, 8], // should have received 0.3334 WETH
  ]);
}

/// start with 900 DAIs on lender and 100 DAIs locally
/// newOffer: wants 0.15 ETHs for 300 DAIs
/// taker snipes (full)
/// now 700 DAIs on lender, 0 locally and 0.15 ETHs
/// newOffer: wants 380 DAIs for 0.2 ETHs
/// borrows 0.05 ETHs using 1080 DAIs of collateral
/// now 1080 DAIs - locked DAI and 0 ETHs (borrower of 0.05 ETHs)
/// newOffer: wants 0.63 ETHs for 1500 DAIs
/// repays the full debt and borrows the missing part in DAI

async function execTraderStrat(makerContract, mgv, lenderName) {
  const dai = await lc.getContract("DAI");
  const wEth = await lc.getContract("WETH");

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);

  // // posting new offer on Mangrove via the MakerContract `post` method
  let offerId = await lc.newOffer(
    mgv,
    makerContract,
    "DAI", //base
    "WETH", //quote
    lc.parseToken("0.15", await lc.getDecimals("WETH")), // required WETH
    lc.parseToken("300.0", await lc.getDecimals("DAI")) // promised DAI (will need to borrow)
  );

  let [takerGot, takerGave] = await lc.snipeSuccess(
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

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);
  await lc.expectAmountOnLender(makerContract, lenderName, [
    ["DAI", lc.parseToken("700", await lc.getDecimals("DAI")), zero, 4],
    ["WETH", takerGave, zero, 8],
  ]);
  // testSigner asks MakerContract to approve Mangrove for base (weth)
  mkrTx2 = await makerContract
    .connect(testSigner)
    .approveMangrove(wEth.address, ethers.constants.MaxUint256);
  await mkrTx2.wait();

  offerId = await lc.newOffer(
    mgv,
    makerContract,
    "WETH", // base
    "DAI", //quote
    lc.parseToken("380.0", await lc.getDecimals("DAI")), // wants DAI
    lc.parseToken("0.2", await lc.getDecimals("WETH")) // promised WETH
  );

  [takerGot, takerGave] = await lc.snipeSuccess(
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

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);
  await lc.expectAmountOnLender(makerContract, lenderName, [
    // dai_on_lender = (1080 * CF_DAI * price_DAI - 0.05 * price_ETH)/price_DAI
    ["WETH", zero, lc.parseToken("0.05", await lc.getDecimals("WETH")), 9],
  ]);

  offerId = await lc.newOffer(
    mgv,
    makerContract,
    "DAI", //base
    "WETH", //quote
    lc.parseToken("0.63", await lc.getDecimals("WETH")), // wants ETH
    lc.parseToken("1500", await lc.getDecimals("DAI")) // gives DAI
  );
  [takerGot, takerGave] = await lc.snipeSuccess(
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
  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);
  //TODO check borrowing DAIs and not borrowing WETHs anymore
}

describe("Deploy strategies", function () {
  this.timeout(100_000); // Deployment is slow so timeout is increased
  let mgv = null;

  before(async function () {
    // 1. mint (1000 dai, 1000 eth, 1000 weth) for testSigner
    // 2. activates (dai,weth) market
    const dai = await lc.getContract("DAI");
    const wEth = await lc.getContract("WETH");
    [testSigner] = await ethers.getSigners();

    await lc.fund([
      ["ETH", "1000.0", testSigner.address],
      ["WETH", "10.0", testSigner.address],
      ["DAI", "10000.0", testSigner.address],
    ]);

    const daiBal = await dai.balanceOf(testSigner.address);
    const wethBal = await wEth.balanceOf(testSigner.address);

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

  // it("Pure lender strat on compound", async function () {
  //   const makerContract = await deployStrat("SimpleCompoundRetail", mgv);
  //   await execLenderStrat(makerContract, mgv, "compound");
  // });

  // it("Lender/borrower strat on compound", async function () {
  //   const makerContract = await deployStrat("AdvancedCompoundRetail", mgv);
  //   await execTraderStrat(makerContract, mgv, "compound");
  // });

  // it("Pure lender strat on aave", async function () {
  //   const makerContract = await deployStrat("SimpleAaveRetail", mgv);
  //   await execLenderStrat(makerContract, mgv, "aave");
  // });

  // it("Lender/borrower strat on aave", async function () {
  //   const makerContract = await deployStrat("AdvancedAaveRetail", mgv);
  //   await execTraderStrat(makerContract, mgv, "aave");
  // });

  // it("Price fed strat", async function () {
  //   const makerContract = await deployStrat("PriceFed", mgv);
  //   await execPriceFedStrat(makerContract, mgv, "aave");
  // });

  // it("Swinging market maker strat", async function () {
  //   const makerContract = await deployStrat("SwingingMarketMaker", mgv);
  //   await execSwingerStrat(makerContract, mgv, "compound");
  // });
});
