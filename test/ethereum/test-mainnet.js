const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers, env, mangrove, network } = require("hardhat");

// TODO Find better way of doing this...
function requireFromProjectRoot(pathFromProjectRoot) {
  return require("./../../" + pathFromProjectRoot);
}

const provider = ethers.provider;
const logger = new ethers.utils.Logger();
const lc = require("../libcommon");

const daiAdmin = env.ethereum.tokens.dai.adminAddress;

async function fund(funding_tuples) {
  async function mintEth(recipient, amount) {
    await network.provider.send("hardhat_setBalance", [
      recipient,
      ethers.utils.hexValue(amount),
    ]);
  }
  for (const tuple of funding_tuples) {
    let token_symbol = tuple[0];
    let amount = tuple[1];
    let recipient = tuple[2];
    const [signer] = await ethers.getSigners();

    switch (token_symbol) {
      case "DAI": {
        let decimals = await lc.dai.decimals();

        amount = lc.parseToken(amount, decimals);
        await network.provider.request({
          method: "hardhat_impersonateAccount",
          params: [daiAdmin],
        });
        admin_signer = provider.getSigner(daiAdmin);
        if ((await admin_signer.getBalance()).eq(0)) {
          await mintEth(daiAdmin, lc.parseToken("1.0"));
        }
        let mintTx = await lc.dai.connect(admin_signer).mint(recipient, amount);
        await mintTx.wait();
        await network.provider.request({
          method: "hardhat_stopImpersonatingAccount",
          params: [daiAdmin],
        });
        break;
      }
      case "WETH": {
        amount = lc.parseToken(amount);
        if (recipient != signer.address) {
          await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [recipient],
          });
          signer = provider.getSigner(recipient);
        }
        let bal = await signer.getBalance();
        if (bal.lt(amount)) {
          await mintEth(recipient, amount);
        }
        let mintTx = await lc.wEth.connect(signer).deposit({ value: amount });
        await mintTx.wait();
        if (recipient != signer.address) {
          await network.provider.request({
            method: "hardhat_stopImpersonateAccount",
            params: [recipient],
          });
        }
        break;
      }
      case "ETH": {
        amount = lc.parseToken(amount);
        await mintEth(recipient, amount);
        break;
      }
      default: {
        console.log("Not implemented ERC funding method: ", token_symbol);
      }
    }
  }
}

async function deployStrat(strategy, mgv) {
  const Strat = await ethers.getContractFactory(strategy);
  let makerContract = null;
  let market = [null,null]; // market pair for lender
  switch (strategy) {
    case "SimpleCompoundRetail":
    case "AdvancedCompoundRetail":
      makerContract = await Strat.deploy(
        lc.comp.address,
        mgv.address,
        lc.wEth.address
      );
      market = [lc.cwEth.address,lc.cDai.address]; 
      break;
    case "SimpleAaveLender":
      makerContract = await Strat.deploy(
        lc.addressProvider.address,
        mgv.address,
        0 // aave referral code
      );
      market = [lc.wEth.address,lc.dai.address]; 
      break;
    default:
      console.warn ("Undefined strategy "+strategy);
  }
  await makerContract.deployed();
  console.log(`Maker contract deployed [${strategy}]`);

  // provisioning Mangrove on behalf of MakerContract
  let overrides = { value: lc.parseToken("2.0", "ETH") };
  tx = await mgv["fund(address)"](makerContract.address, overrides);
  await tx.wait();

  lc.assertEqualBN(
    await mgv.balanceOf(makerContract.address),
    lc.parseToken("2.0", "ETH"),
    "Failed to fund the Mangrove"
  );
  console.log("Mangrove is provisioned");

  // testSigner approves Mangrove for WETH before trying to take offer
  tkrTx = await lc.wEth
    .connect(testSigner)
    .approve(mgv.address, ethers.constants.MaxUint256);
  await tkrTx.wait();

  allowed = await lc.wEth.allowance(testSigner.address, mgv.address);
  lc.assertEqualBN(allowed, ethers.constants.MaxUint256, "Approve failed");
  console.log("Test signer has approved quote for payment");

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
    .approveMangrove(lc.dai.address, ethers.constants.MaxUint256);
  // One sends 1000 DAI to MakerContract
  mkrTxs[i++] = await lc.dai
    .connect(testSigner)
    .transfer(makerContract.address, lc.parseToken("1000.0", "DAI"));
  // testSigner asks makerContract to approve lender to be able to mint [x]Token
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
  console.log("Maker contract is ready");
  /***********************************************************************/
  return makerContract;
}

async function logLenderStatus(makerContract, lenderName, tokens) {
  switch(lenderName){
    case "compound" :
      lc.logCompoundStatus(makerContract, tokens);  
      break; 
    case "aave":
      lc.logAaveStatus(makerContract, tokens);
      break;
  }
}

async function expectAmountOnLender(makerContract, lenderName, expectDai, expectWeth) {
  let balwEth = 0;
  let balDai = 0;
  switch(lenderName) {
    case "compound" :
      balwEth = await lc.cwEth
      .connect(testSigner)
      .callStatic.balanceOfUnderlying(makerContract.address);
      balDai = await lc.cDai
      .connect(testSigner)
      .callStatic.balanceOfUnderlying(makerContract.address);
      break;
    case "aave":
      balwEth = await lc.awEth
      .connect(testSigner)
      .callStatic.balanceOf(makerContract.address);
      balDai = await lc.aDai
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
    // 1. mint (1000 lc.dai, 1000 eth, 1000 weth) for testSigner
    // 2. activates (dai,weth) market
    [testSigner] = await ethers.getSigners();
    testRunner = testSigner.address;
    bal = await testSigner.getBalance();
    await lc.setDecimals();

    await fund([
      ["ETH", "1.0", daiAdmin],
      ["ETH", "1000.0", testRunner],
      ["WETH", "5.0", testRunner],
      ["DAI", "10000.0", testRunner],
    ]);

    const daiBal = await lc.dai.balanceOf(testRunner);
    const wethBal = await lc.wEth.balanceOf(testRunner);

    lc.assertEqualBN(daiBal, lc.parseToken("10000.0", "DAI"));
    lc.assertEqualBN(
      wethBal,
      lc.parseToken("5.0", "WETH"),
      "Minting WETH failed"
    );

    mgv = await lc.deployMangrove();
    await lc.activateMarket(mgv, lc.dai.address, lc.wEth.address);

    let cfg = await mgv.callStatic.getConfig(lc.dai.address, lc.wEth.address);
    assert(cfg.local.active, "Market is inactive");
  });

  it("Pure lender strat on compound", async function () {
    const makerContract = await deployStrat("SimpleCompoundRetail", mgv);
    let accrueTx = await lc.cDai.connect(testSigner).accrueInterest();
    let receipt = await accrueTx.wait(0);

    await logLenderStatus(makerContract, testSigner, "compound", [lc.dai, lc.wEth]);
    
    // cheat to retrieve next assigned offer ID for the next newOffer
    let offerId = await lc.nextOfferId(
      lc.dai.address,
      lc.wEth.address,
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

    [offer] = await mgv.offerInfo(lc.dai.address, lc.wEth.address, offerId);
    lc.assertEqualBN(
      offer.gives,
      lc.parseToken("1000.0", "DAI"),
      "Offer not correctly inserted"
    );

    // dry running snipe buy order first
    let [success, takerGot, takerGave] = await mgv.callStatic.snipe(
      lc.dai.address, // maker base
      lc.wEth.address, // maker quote
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

    accrueTx = await lc.cDai.connect(testSigner).accrueInterest();
    receipt = await accrueTx.wait(0);

    await logLenderStatus(makerContract, "compound", [lc.wEth, lc.dai]);
  });

  it("Lender/borrower strat", async function () {
    const makerContract = await deployStrat("AdvancedCompoundRetail", mgv);
    /***********************************************************************/

    let accrueTx = await lc.cDai.connect(testSigner).accrueInterest();
    await accrueTx.wait(0);

    await logLenderStatus(makerContract, "compound", [lc.wEth, lc.dai]);
    // cheat to retrieve next assigned offer ID for the next newOffer
    let offerId = await lc.nextOfferId(
      lc.dai.address,
      lc.wEth.address,
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

    let [offer] = await mgv.offerInfo(lc.dai.address, lc.wEth.address, offerId);
    lc.assertEqualBN(
      offer.gives,
      lc.parseToken("300.0", "DAI"),
      "Offer not correctly inserted"
    );

    // dry running snipe buy order first
    let [success, takerGot, takerGave] = await mgv.callStatic.snipe(
      lc.dai.address, // maker base
      lc.wEth.address, // maker quote
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
    let balEthComp = await lc.cwEth
      .connect(testSigner)
      .callStatic.balanceOfUnderlying(makerContract.address);
    let balDaiComp = await lc.cDai
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

    accrueTx = await lc.cDai.connect(testSigner).accrueInterest();
    receipt = await accrueTx.wait(0);

    await logLenderStatus(makerContract, "compound", [lc.wEth, lc.dai]);
    offerId = await lc.nextOfferId(
      lc.wEth.address,
      lc.dai.address,
      makerContract
    );

    // testSigner asks MakerContract to approve Mangrove for base (weth)
    mkrTx2 = await makerContract
      .connect(testSigner)
      .approveMangrove(lc.wEth.address, ethers.constants.MaxUint256);
    await mkrTx2.wait();

    await lc.newOffer(
      makerContract,
      "WETH",
      "DAI",
      lc.parseToken("0.2", "WETH"), // promised WETH
      lc.parseToken("380.0", "DAI") // required DAI
    );

    // taker approves mgv for DAI erc
    tkrTx = await lc.dai
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
    await logLenderStatus(makerContract, "compound", [lc.wEth, lc.dai]);
  });
});
