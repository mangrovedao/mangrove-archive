const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers, env, mangrove, network } = require("hardhat");

const provider = ethers.provider;
const lc = require("./libcommon");

const dai = lc.getContract("DAI");
const wEth = lc.getContract("WETH");
const comp = lc.getContract("COMP");
//const aave = lc.getContract("AAVE");
const cwEth = lc.getContract("CWETH");
const cDai = lc.getContract("CDAI");
//const awEth = lc.getContract("AWETH");
//const aDai = lc.getContract("ADAI");

async function deployStrat(strategy, mgv) {
  const Strat = await ethers.getContractFactory(strategy);
  let makerContract = null;
  let market = [null,null]; // market pair for lender
  switch (strategy) {
    case "SimpleCompoundRetail":
    case "AdvancedCompoundRetail":
      makerContract = await Strat.deploy(
        comp.address,
        mgv.address,
        wEth.address
      );
      market = [cwEth.address,cDai.address]; 
      break;
    case "SimpleAaveRetail":
      makerContract = await Strat.deploy(
        aave.addressesProvider.address,
        mgv.address,
        0 // aave referral code
      );
      market = [wEth.address,dai.address]; 
      break;
    default:
      console.warn ("Undefined strategy "+strategy);
  }
  await makerContract.deployed();

  // provisioning Mangrove on behalf of MakerContract
  let overrides = { value: lc.parseToken("2.0", "ETH") };
  tx = await mgv["fund(address)"](makerContract.address, overrides);
  await tx.wait();

  lc.assertEqualBN(
    await mgv.balanceOf(makerContract.address),
    lc.parseToken("2.0", "ETH"),
    "Failed to fund the Mangrove"
  );

  // testSigner approves Mangrove for WETH before trying to take offer
  tkrTx = await wEth
    .connect(testSigner)
    .approve(mgv.address, ethers.constants.MaxUint256);
  await tkrTx.wait();

  allowed = await wEth.allowance(testSigner.address, mgv.address);
  lc.assertEqualBN(allowed, ethers.constants.MaxUint256, "Approve failed");

  /*********************** MAKER SIDE PREMICES **************************/
  let mkrTxs = [];
  let i = 0;
  // offer should get/put base/quote tokens on lender contract (OK since `testSigner` is MakerContract admin)
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .enterMarkets(market);
  
  // testSigner asks MakerContract to approve Mangrove for base (DAI)
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .approveMangrove(dai.address, ethers.constants.MaxUint256);
  // One sends 1000 DAI to MakerContract
  mkrTxs[i++] = await dai
    .connect(testSigner)
    .transfer(makerContract.address, lc.parseToken("1000.0", "DAI"));
  // testSigner asks makerContract to approve lender to be able to mint [c/a]Token
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .approve(market[0], ethers.constants.MaxUint256);
  // NB in the special case of cEth this is not necessary
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .approve(market[1], ethers.constants.MaxUint256);
  
  // makerContract deposits some DAI on Lender (remains 100 DAIs on the contract)
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .mint(market[1], lc.parseToken("900.0", "DAI"));
  
  await lc.synch(mkrTxs);
  /***********************************************************************/
  return makerContract;
}

async function logLenderStatus(makerContract, lenderName, tokens) {  
  switch(lenderName){
    case "compound" :
      await lc.logCompoundStatus(makerContract, tokens);  
      break; 
    case "aave":
      await lc.logAaveStatus(makerContract, tokens);
      break;
    default :
      console.warn("Lender not recognized: ", lenderName);
  }
}

async function expectAmountOnLender(makerContract, lenderName, expectDai, expectWeth) {
  let balwEth = 0;
  let balDai = 0;
  switch(lenderName) {
    case "compound" :
      balwEth = await cwEth
      .connect(testSigner)
      .callStatic.balanceOfUnderlying(makerContract.address);
      balDai = await cDai
      .connect(testSigner)
      .callStatic.balanceOfUnderlying(makerContract.address);
      break;
    case "aave":
      balwEth = await awEth
      .connect(testSigner)
      .callStatic.balanceOf(makerContract.address);
      balDai = await aDai
      .connect(testSigner)
      .callStatic.balanceOfUnderlying(makerContract.address);
      break;
  }
    // checking that MakerContract did put received WETH on compound (as cETH) --allowing 5 gwei of rounding error
  lc.assertAlmost(
    expectWeth,
    balwEth,
    9,
    "Incorrect Eth amount on Lender"
  );
  lc.assertAlmost(
    expectDai,
    balDai,
    4,
    "Incorrect Dai amount on Lender"
  );
}

describe("Deploy strategies", function () {
  this.timeout(100_000); // Deployment is slow so timeout is increased
  testSigner = null;
  testRunner = null;
  mgv = null;

  before(async function () {
    // 1. mint (1000 dai, 1000 eth, 1000 weth) for testSigner
    // 2. activates (dai,weth) market
    [testSigner] = await ethers.getSigners();
    testRunner = testSigner.address;
    bal = await testSigner.getBalance();
    await lc.setDecimals();

    await lc.fund([
      ["ETH", "1000.0", testRunner],
      ["WETH", "5.0", testRunner],
      ["DAI", "10000.0", testRunner],
    ]);

    const daiBal = await dai.balanceOf(testRunner);
    const wethBal = await wEth.balanceOf(testRunner);

    lc.assertEqualBN(daiBal, lc.parseToken("10000.0", "DAI"));
    lc.assertEqualBN(
      wethBal,
      lc.parseToken("5.0", "WETH"),
      "Minting WETH failed"
    );

    mgv = await lc.deployMangrove();
    await lc.activateMarket(mgv, dai.address, wEth.address);

    let cfg = await mgv.callStatic.getConfig(dai.address, wEth.address);
    assert(cfg.local.active, "Market is inactive");
  });

  it("Pure lender strat on compound", async function () {
    const makerContract = await deployStrat("SimpleCompoundRetail", mgv);
    let accrueTx = await cDai.connect(testSigner).accrueInterest();
    let receipt = await accrueTx.wait(0);

    await logLenderStatus(makerContract, "compound", ["DAI", "WETH"]);
    
    // cheat to retrieve next assigned offer ID for the next newOffer
    let offerId = await lc.nextOfferId(
      dai.address,
      wEth.address,
      makerContract
    );

    // // posting new offer on Mangrove via the MakerContract `post` method
    await lc.newOffer(
      makerContract,
      "DAI",
      "WETH",
      lc.parseToken("1000.0", "DAI"), // promised DAI
      lc.parseToken("0.5", "WETH") // required WETH
    );

    [offer] = await mgv.offerInfo(dai.address, wEth.address, offerId);
    lc.assertEqualBN(
      offer.gives,
      lc.parseToken("1000.0", "DAI"),
      "Offer not correctly inserted"
    );

    // dry running snipe buy order first
    let [success, takerGot, takerGave] = await mgv.callStatic.snipe(
      dai.address, // maker base
      wEth.address, // maker quote
      offerId,
      lc.parseToken("800.0", "DAI"), // taker wants 800 DAI (takes 0.1 from contract and 0.7 from compound)
      lc.parseToken("0.5", "WETH"), // taker is ready to give up-to 0.5 WETH will give 0.4 WETH
      ethers.constants.MaxUint256, // max gas
      true //fillWants
    );

    assert(success, "Snipe failed");
    lc.assertEqualBN(
      takerGot,
      lc.netOf(lc.parseToken("800.0", "DAI"), fee),
      "Incorrect received amount"
    );
    lc.assertEqualBN(
      takerGave,
      lc.parseToken("0.4", "WETH"),
      "Incorrect given amount"
    );

    await lc.snipe(
      mgv,
      "DAI", // maker base
      "WETH", // maker quote
      offerId,
      lc.parseToken("800.0", "DAI"), // taker wants 0.8 DAI
      lc.parseToken("0.5", "WETH") // taker is ready to give up-to 0.5 WETH
    );

    // checking that MakerContract did put WETH on lender --allowing 5 gwei of rounding error
    await expectAmountOnLender(makerContract, "compound", lc.parseToken("200", "DAI"), takerGave);

    accrueTx = await cDai.connect(testSigner).accrueInterest();
    receipt = await accrueTx.wait(0);

    await logLenderStatus(makerContract, "compound", ["WETH", "DAI"]);
  });

  it("Lender/borrower strat on compound", async function () {
    const makerContract = await deployStrat("AdvancedCompoundRetail", mgv);
    /***********************************************************************/

    let accrueTx = await cDai.connect(testSigner).accrueInterest();
    await accrueTx.wait(0);

    await logLenderStatus(makerContract, "compound", ["WETH", "DAI"]);
    // cheat to retrieve next assigned offer ID for the next newOffer
    let offerId = await lc.nextOfferId(
      dai.address,
      wEth.address,
      makerContract
    );

    // // posting new offer on Mangrove via the MakerContract `post` method
    await lc.newOffer(
      makerContract,
      "DAI",
      "WETH",
      lc.parseToken("300.0", "DAI"), // promised DAI (will need to borrow)
      lc.parseToken("0.15", "WETH") // required WETH
    );

    let [offer] = await mgv.offerInfo(dai.address, wEth.address, offerId);
    lc.assertEqualBN(
      offer.gives,
      lc.parseToken("300.0", "DAI"),
      "Offer not correctly inserted"
    );

    // dry running snipe buy order first
    let [success, takerGot, takerGave] = await mgv.callStatic.snipe(
      dai.address, // maker base
      wEth.address, // maker quote
      offerId,
      lc.parseToken("300", "DAI"),
      lc.parseToken("0.15", "WETH"),
      ethers.constants.MaxUint256, // max gas
      true //fillWants
    );

    assert(success, "Snipe failed");
    lc.assertEqualBN(
      takerGot,
      lc.netOf(lc.parseToken("300", "DAI"), fee),
      "Incorrect received amount"
    );
    lc.assertEqualBN(
      takerGave,
      lc.parseToken("0.15", "WETH"),
      "Incorrect given amount"
    );

    await lc.snipe(
      mgv,
      "DAI", // maker base
      "WETH", // maker quote
      offerId,
      lc.parseToken("300", "DAI"),
      lc.parseToken("0.15", "WETH")
    );

    await snipeTx.wait();

    //await expectAmountOnLender(makerContract, "compound", lc.parseToken("200", "DAI"), takerGave);

    /// testing status of makerContract's compound pools.
    let balEthComp = await cwEth
      .connect(testSigner)
      .callStatic.balanceOfUnderlying(makerContract.address);
    let balDaiComp = await cDai
      .connect(testSigner)
      .callStatic.balanceOfUnderlying(makerContract.address);

    // checking that MakerContract did put received WETH on compound (as cETH) --allowing 5 gwei of rounding error
    lc.assertAlmost(
      takerGave,
      balEthComp,
      8,
      "Incorrect Eth amount on Compound"
    );
    // checking that MakerContract did get 0.7 ethers of DAI from compound (= 0.8 - 0.1 from contract provision)
    // maker gave 300, taking 100 directly from MakerContract and 200 from compound
    // remaining balance on compound should be ~ 900 - 200 = 700
    lc.assertAlmost(
      lc.parseToken("700", "DAI"),
      balDaiComp,
      4,
      "Incorrect Dai amount on Compound " + lc.formatToken(balDaiComp, "DAI")
    );

    accrueTx = await cDai.connect(testSigner).accrueInterest();
    receipt = await accrueTx.wait(0);

    await logLenderStatus(makerContract, "compound", ["WETH", "DAI"]);
    offerId = await lc.nextOfferId(
      wEth.address,
      dai.address,
      makerContract
    );

    // testSigner asks MakerContract to approve Mangrove for base (weth)
    mkrTx2 = await makerContract
      .connect(testSigner)
      .approveMangrove(wEth.address, ethers.constants.MaxUint256);
    await mkrTx2.wait();

    await lc.newOffer(
      makerContract,
      "WETH",
      "DAI",
      lc.parseToken("0.2", "WETH"), // promised WETH
      lc.parseToken("380.0", "DAI") // required DAI
    );

    // taker approves mgv for DAI erc
    tkrTx = await dai
      .connect(testSigner)
      .approve(mgv.address, ethers.constants.MaxUint256);
    await tkrTx.wait();

    await lc.snipe(
      mgv,
      "WETH",
      "DAI",
      offerId,
      lc.parseToken("0.2", "WETH"), // wanted WETH
      lc.parseToken("380.0", "DAI") // giving DAI
    );
    await logLenderStatus(makerContract, "compound", ["WETH", "DAI"]);
  });

  // it("Pure lender strat on aave", async function () {
  //   const makerContract = await deployStrat("SimpleAaveRetail", mgv);
  //   console.log(makerContract);
  // });

});
