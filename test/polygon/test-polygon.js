const { ethers, env, network } = require("hardhat");

const { assert } = require("chai");

const lc = require("../libcommon");

const provider = hre.ethers.provider;
const chainMgr = env.polygon.admin.childChainManager;
const admin_signer = provider.getSigner(chainMgr);

async function fund(funding_tuples) {
  async function mintMATIC(recipient, amount) {
    console.log("Providing gas tokens to " + recipient);
    await network.provider.send("hardhat_setBalance", [
      recipient,
      ethers.utils.hexValue(amount),
    ]);
  }
  async function mintChildErc(contract, recipient, amount) {
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [chainMgr],
    });
    if ((await admin_signer.getBalance()).eq(0)) {
      await mintMATIC(chainMgr, lc.parseToken("1.0"));
    }
    // console.log(lc.formatToken(await admin_signer.getBalance(), "MATIC"));
    // console.log("here");
    let mintTx = await contract
      .connect(admin_signer)
      .deposit(recipient, amount);
    await mintTx.wait();
    await network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [chainMgr],
    });
  }

  for (const tuple of funding_tuples) {
    let token_symbol = tuple[0];
    let amount = tuple[1];
    let recipient = tuple[2];
    console.log(`Minting ${token_symbol} on polygon`);
    switch (token_symbol) {
      case "DAI": {
        //converting amount into bytes32
        amount = ethers.utils.hexZeroPad(lc.parseToken(amount, "DAI"), 32);
        await mintChildErc(lc.dai, recipient, amount);
        break;
      }
      case "WETH": {
        //converting amount into bytes32
        amount = ethers.utils.hexZeroPad(lc.parseToken(amount, "WETH"), 32);
        await mintChildErc(lc.wEth, recipient, amount);
        break;
      }
      case "MATIC": {
        amount = lc.parseToken(amount);
        await mintMATIC(recipient, amount);
        break;
      }
      default: {
        console.warn("Not implemented ERC funding method: ", token_symbol);
      }
    }
  }
}

async function logBalances() {
  const [testSigner] = await ethers.getSigners();
  console.log(
    "testRunner MATIC",
    lc.formatToken(await testSigner.getBalance(), "MATIC")
  );
  console.log(
    "testRunner DAI",
    lc.formatToken(await lc.dai.balanceOf(testSigner.address), "DAI")
  );
  console.log(
    "testRunner wEth",
    lc.formatToken(await lc.wEth.balanceOf(testSigner.address), "WETH")
  );
  console.log(
    "chainManager's MATIC",
    lc.formatToken(await admin_signer.getBalance(), "MATIC")
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
      ["WETH", "5.0", testRunner],
      ["DAI", "10000.0", testRunner],
    ]);

    let daiBal = await lc.dai.balanceOf(testRunner);
    let wethBal = await lc.wEth.balanceOf(testRunner);

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

  // it("should deploy simple strategy", async function () {

  //     const MangroveOffer = await ethers.getContractFactory("MangroveOffer");
  //     const makerContract = await MangroveOffer.deploy(mgv.address);
  //     await makerContract.deployed();

  //     let overrides = {value:lc.parseToken("1.0", 'ETH')};

  //     // testRunner provisions Mangrove for makerContract's bounty
  //     await mgv["fund(address)"](makerContract.address,overrides);
  //     lc.assertEqualBN(
  //         await mgv.balanceOf(makerContract.address),
  //         lc.parseToken("1.0",'ETH'),
  //         "Failed to fund the Mangrove"
  //     );

  //     // cheat to retrieve next assigned offer ID for the next newOffer
  //     offerId = await lc.nextOfferId(lc.dai.address,lc.wEth.address,makerContract);

  //     // posting new offer on Mngrove via the MakerContract `post` method
  //     await lc.newOffer(
  //         makerContract,
  //         'DAI',
  //         'WETH',
  //         lc.parseToken("1000.0", 'DAI'),
  //         lc.parseToken("0.5", 'WETH'),
  //     );
  //     //await postTx.wait();

  //     [offer, ] = await mgv.offerInfo(lc.dai.address, lc.wEth.address, offerId);
  //     lc.assertEqualBN(
  //         offer.gives,
  //         lc.parseToken("1000.0", 'DAI'),
  //         "Offer not correctly inserted"
  //     );
  // });

  it("Pure lender strat", async function () {
    await logBalances();

    const SimpleRetail = await ethers.getContractFactory("SimpleRetail");
    const makerContract = await SimpleRetail.deploy(
      lc.comp.address,
      mgv.address,
      lc.wEth.address
    );
    await makerContract.deployed();

    let overrides = { value: lc.parseToken("1.0", "MATIC") };
    tx = await mgv["fund(address)"](makerContract.address, overrides);
    await tx.wait();

    lc.assertEqualBN(
      await mgv.balanceOf(makerContract.address),
      lc.parseToken("1.0", "MATIC"),
      "Failed to fund the Mangrove"
    );

    /*********************** TAKER SIDE PREMICES **************************/

    // testSigner approves Mangrove for WETH before trying to take offer
    tkrTx = await lc.wEth
      .connect(testSigner)
      .approve(mgv.address, ethers.constants.MaxUint256);
    await tkrTx.wait();

    allowed = await lc.wEth.allowance(testSigner.address, mgv.address);
    lc.assertEqualBN(allowed, ethers.constants.MaxUint256, "Approve failed");

    /***********************************************************************/

    /*********************** MAKER SIDE PREMICES **************************/
    const mkrTxs = [];
    let i = 0;
    // offer should get/put base/quote tokens on compound (OK since `testSigner` is MakerContract admin)
    mkrTxs[i++] = await makerContract
      .connect(testSigner)
      .enterMarkets([lc.cwEth.address, lc.cDai.address]);
    // testSigner asks MakerContract to approve Mangrove for base (DAI)
    mkrTxs[i++] = await makerContract
      .connect(testSigner)
      .approveMangrove(lc.dai.address, ethers.constants.MaxUint256);
    // One sends 1000 DAI to MakerContract
    mkrTxs[i++] = await lc.dai
      .connect(testSigner)
      .transfer(makerContract.address, lc.parseToken("1000.0", "DAI"));
    // testSigner asks makerContract to approve cDai to be able to mint cDAI
    mkrTxs[i++] = await makerContract
      .connect(testSigner)
      .approveCToken(lc.cDai.address, ethers.constants.MaxUint256);
    // testSigner asks makerContract to approve cwEth to be able to mint cwEth
    mkrTxs[i++] = await makerContract
      .connect(testSigner)
      .approveCToken(lc.cwEth.address, ethers.constants.MaxUint256);
    // makerContract deposits some DAI on Compound (remains 100 DAIs on the contract)
    mkrTxs[i++] = await makerContract
      .connect(testSigner)
      .mintCToken(lc.cDai.address, lc.parseToken("900.0", "DAI"));

    await lc.synch(mkrTxs);
    /***********************************************************************/
    //console.log("here 1");

    accrueTx = await lc.cDai.connect(testSigner).accrueInterest();
    receipt = await accrueTx.wait(0);

    await lc.logCompoundStatus(makerContract, ["WETH", "DAI"]);
    // cheat to retrieve next assigned offer ID for the next newOffer
    offerId = await lc.nextOfferId(
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
    console.log("Sniping with an offer of 0.5 WETH for 800 DAI...");
    [success, takerGot, takerGave] = await mgv.callStatic.snipe(
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

    /// testing status of makerContract's compound pools.
    balEthComp = await lc.cwEth
      .connect(testSigner)
      .callStatic.balanceOfUnderlying(makerContract.address);
    balDaiComp = await lc.cDai
      .connect(testSigner)
      .callStatic.balanceOfUnderlying(makerContract.address);

    // checking that MakerContract did put received WETH on compound (as cETH) --allowing 5 gwei of rounding error
    lc.assertAlmost(
      takerGave,
      balEthComp,
      9,
      "Incorrect Eth amount on Compound"
    );
    // checking that MakerContract did get 0.7 ethers of DAI from compound (= 0.8 - 0.1 from contract provision)
    // maker gave 800, taking 100 directly from MakerContract and 700 from compound
    // remaining balance on compound should be ~ 200
    expected = lc.parseToken("200", "DAI");
    lc.assertAlmost(
      expected,
      balDaiComp,
      4,
      "Incorrect Dai amount on Compound"
    );

    accrueTx = await lc.cDai.connect(testSigner).accrueInterest();
    receipt = await accrueTx.wait(0);

    await lc.logCompoundStatus(makerContract, ["WETH", "DAI"]);
  });

  it("Lender/borrower strat", async function () {
    const AdvancedRetail = await ethers.getContractFactory("AdvancedRetail");
    const makerContract = await AdvancedRetail.deploy(
      lc.comp.address,
      mgv.address,
      lc.wEth.address
    );
    await makerContract.deployed();

    let overrides = { value: lc.parseToken("10.0", "ETH") };
    tx = await mgv["fund(address)"](makerContract.address, overrides);
    await tx.wait();

    /*********************** MAKER SIDE PREMICES **************************/
    const mkrTxs = [];
    let i = 0;
    mkrTxs[i++] = await makerContract
      .connect(testSigner)
      .enterMarkets([lc.cwEth.address, lc.cDai.address]);
    // testSigner asks MakerContract to approve Mangrove for base (DAI)
    mkrTxs[i++] = await makerContract
      .connect(testSigner)
      .approveMangrove(lc.dai.address, ethers.constants.MaxUint256);
    // testSigner provisions MakerContract with DAI
    mkrTxs[i++] = await lc.dai
      .connect(testSigner)
      .transfer(makerContract.address, lc.parseToken("250.0", "DAI"));
    // testSigner asks makerContract to approve cDai to be able to mint cDAI
    mkrTxs[i++] = await makerContract
      .connect(testSigner)
      .approveCToken(lc.cDai.address, ethers.constants.MaxUint256);
    // testSigner asks makerContract to approve cwEth to be able to mint cwEth
    mkrTxs[i++] = await makerContract
      .connect(testSigner)
      .approveCToken(lc.cwEth.address, ethers.constants.MaxUint256);
    // makerContract deposits some DAI on Compound (remains 100 DAIs on the contract)
    mkrTxs[i++] = await makerContract
      .connect(testSigner)
      .mintCToken(lc.cDai.address, lc.parseToken("200", "DAI"));

    await lc.synch(mkrTxs);

    /***********************************************************************/

    accrueTx = await lc.cDai.connect(testSigner).accrueInterest();
    receipt = await accrueTx.wait(0);

    await lc.logCompoundStatus(makerContract, ["WETH", "DAI"]);
    // cheat to retrieve next assigned offer ID for the next newOffer
    offerId = await lc.nextOfferId(
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

    [offer] = await mgv.offerInfo(lc.dai.address, lc.wEth.address, offerId);
    lc.assertEqualBN(
      offer.gives,
      lc.parseToken("300.0", "DAI"),
      "Offer not correctly inserted"
    );

    // dry running snipe buy order first
    [success, takerGot, takerGave] = await mgv.callStatic.snipe(
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

    /// testing status of makerContract's compound pools.
    balEthComp = await lc.cwEth
      .connect(testSigner)
      .callStatic.balanceOfUnderlying(makerContract.address);
    balDaiComp = await lc.cDai
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
    // maker gave 800, taking 100 directly from MakerContract and 700 from compound
    // remaining balance on compound should be ~ 200
    lc.assertAlmost(
      balDaiComp,
      balDaiComp,
      4,
      "Incorrect Dai amount on Compound " + lc.formatToken(balDaiComp, "DAI")
    );

    accrueTx = await lc.cDai.connect(testSigner).accrueInterest();
    receipt = await accrueTx.wait(0);

    await lc.logCompoundStatus(makerContract, ["WETH", "DAI"]);
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
    await lc.logCompoundStatus(makerContract, ["WETH", "DAI"]);
  });
});
