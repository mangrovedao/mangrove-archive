require("dotenv-flow").config(); // Reads local environment variables from .env*.local files
const config = require("config"); // Reads configuration files from /config/
const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

// TODO Find better way of doing this...
function requireFromProjectRoot(pathFromProjectRoot) {
  return require("./../../" + pathFromProjectRoot);
}

// FIXME Nået hertil - tag Ethereum env i brug

// Address of Join (has auth) https://changelog.makerdao.com/ -> releases -> contract addresses -> MCD_JOIN_DAI
const daiAddress = config.get("ethereum.tokens.dai.address");
const cDaiAddress = config.get("ethereum.tokens.cDai.address");
const wethAddress = config.get("ethereum.tokens.wEth.address");
const cEthAddress = config.get("ethereum.tokens.cEth.address");
const unitrollerAddress = config.get("ethereum.compound.unitrollerAddress");

const daiAbi = requireFromProjectRoot(config.get("ethereum.tokens.dai.abi"));
const wethAbi = requireFromProjectRoot(config.get("ethereum.tokens.wEth.abi"));
const cErc20Abi = requireFromProjectRoot(
  config.get("ethereum.tokens.cDai.abi")
);
const cEthAbi = requireFromProjectRoot(config.get("ethereum.tokens.cEth.abi"));

const compAbi = requireFromProjectRoot(
  config.get("ethereum.compound.unitrollerAbi")
);

const provider = hre.ethers.provider;
const logger = new ethers.utils.Logger();

const dai = new ethers.Contract(daiAddress, daiAbi, provider);
const cDai = new ethers.Contract(cDaiAddress, cErc20Abi, provider);
const weth = new ethers.Contract(wethAddress, wethAbi, provider);
const cEth = new ethers.Contract(cEthAddress, cEthAbi, provider);
const comp = new ethers.Contract(unitrollerAddress, compAbi, provider);

const daiAdmin = config.get("ethereum.tokens.dai.admin"); // to mint fresh DAIs
const compoundWhale = config.get("ethereum.compound.whale");

const decimals = new Map();

function assertEqualBN(value1, value2, msg) {
  errorMsg =
    msg +
    ("(Received: " +
      value1.toString() +
      ", Expected: " +
      value2.toString() +
      ")");
  assert(value1.eq(value2), errorMsg);
}

async function nextOfferId(base, quote, ctr) {
  offerId = await ctr.callStatic.newOffer(
    base,
    quote,
    parseToken("1.0"),
    0,
    0,
    0,
    0
  );
  return offerId;
}

async function synch(promises) {
  for (let i = 0; i < promises.length; i++) {
    await promises[i].wait();
  }
}

function netOf(bn, fee) {
  return bn.sub(bn.mul(fee).div(10000));
}

async function fund(funding_tuples) {
  async function mintEth(recipient, amount) {
    await hre.network.provider.send("hardhat_setBalance", [
      recipient,
      ethers.utils.hexValue(amount),
    ]);
  }
  for (const tuple of funding_tuples) {
    let token_symbol = tuple[0];
    let amount = tuple[1];
    let recipient = tuple[2];
    [owner] = await ethers.getSigners();
    let signer = owner;

    switch (token_symbol) {
      case "DAI": {
        let decimals = await dai.decimals();
        amount = parseToken(amount, decimals);
        await hre.network.provider.request({
          method: "hardhat_impersonateAccount",
          params: [daiAdmin],
        });
        admin_signer = await provider.getSigner(daiAdmin);
        if ((await admin_signer.getBalance()).eq(0)) {
          await mintEth(daiAdmin, parseToken("1.0"));
        }
        let mintTx = await dai.connect(admin_signer).mint(recipient, amount);
        await mintTx.wait();
        await hre.network.provider.request({
          method: "hardhat_stopImpersonatingAccount",
          params: [daiAdmin],
        });
        break;
      }
      case "WETH": {
        amount = parseToken(amount);
        if (recipient != owner.address) {
          await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [recipient],
          });
          signer = await provider.getSigner(recipient);
        }
        let bal = await signer.getBalance();
        if (bal.lt(amount)) {
          await mintEth(recipient, amount);
        }
        let mintTx = await weth.connect(signer).deposit({ value: amount });
        await mintTx.wait();
        if (recipient != owner.address) {
          await hre.network.provider.request({
            method: "hardhat_stopImpersonateAccount",
            params: [recipient],
          });
        }
        break;
      }
      case "ETH": {
        amount = parseToken(amount);
        await mintEth(recipient, amount);
        break;
      }
      default: {
        console.log("Not implemented ERC funding method: ", token_symbol);
      }
    }
  }
}

async function deployMangrove() {
  const Mangrove = await ethers.getContractFactory("Mangrove");
  mgv_gasprice = 500;
  let gasmax = 2000000;
  mgv = await Mangrove.deploy(mgv_gasprice, gasmax);
  await mgv.deployed();
  receipt = await mgv.deployTransaction.wait(0);
  // console.log("GasUsed during deploy: ", receipt.gasUsed.toString());

  //activating (dai,weth) market
  fee = 30; // setting fees to 0.03%
  density = 10000;
  overhead_gasbase = 20000;
  offer_gasbase = 20000;
  activateTx = await mgv.activate(
    daiAddress,
    wethAddress,
    fee,
    density,
    overhead_gasbase,
    offer_gasbase
  );
  await activateTx.wait();

  //activating (weth,dai) market
  fee = 30; // setting fees to 0.03%
  density = 10000;
  overhead_gasbase = 20000;
  offer_gasbase = 20000;
  activateTx = await mgv.activate(
    wethAddress,
    daiAddress,
    fee,
    density,
    overhead_gasbase,
    offer_gasbase
  );
  await activateTx.wait();
  return mgv;
}

function assertAlmost(bignum_expected, bignum_obs, decimal, msg) {
  error = bignum_expected.div(ethers.utils.parseUnits("1.0", decimal));
  if (bignum_expected.lte(bignum_obs)) {
    assert(
      bignum_obs.sub(bignum_expected).lte(error),
      msg +
        ":\n " +
        "\x1b[32mExpected: " +
        formatToken(bignum_expected, 18) +
        "\n\x1b[31mGiven: " +
        formatToken(bignum_obs, 18) +
        "\x1b[0m\n"
    );
  } else {
    assert(
      bignum_expected.sub(bignum_obs).lte(error),
      msg +
        ":\n" +
        "\x1b[32mExpected: " +
        formatToken(bignum_expected, 18) +
        "\n\x1b[31mGiven: " +
        formatToken(bignum_obs, 18) +
        "\x1b[0m\n"
    );
  }
}

async function logCompoundStatus(contract, symbols) {
  function logPosition(s, x, y, z) {
    console.log(
      s,
      ":",
      " (\x1b[32m",
      x,
      "\x1b[0m|\x1b[31m",
      y,
      "\x1b[0m) + \x1b[34m",
      z,
      "\x1b[0m"
    );
  }
  [, liquidity] = await comp.getAccountLiquidity(contract.address);
  console.log();
  console.log(
    "**** Account borrow power (USD): \x1b[35m",
    formatToken(liquidity, 18),
    "\x1b[0m ****"
  );
  for (const symbol of symbols) {
    switch (symbol) {
      case "DAI":
        [, redeemableDai] = await contract.maxGettableUnderlying(cDaiAddress);
        [, , borrowBalance] = await cDai.getAccountSnapshot(contract.address);
        daiBalance = await dai.balanceOf(contract.address);
        logPosition(
          "DAI",
          formatToken(redeemableDai, "DAI"),
          formatToken(borrowBalance, "DAI"),
          formatToken(daiBalance, "DAI")
        );
        break;
      case "WETH":
        [, redeemableWeth] = await contract.maxGettableUnderlying(cEthAddress);
        [, , borrowBalance] = await cEth.getAccountSnapshot(contract.address);
        wethBalance = await weth.balanceOf(contract.address);
        logPosition(
          "WETH",
          formatToken(redeemableWeth, "DAI"),
          formatToken(borrowBalance, "DAI"),
          formatToken(wethBalance, "DAI")
        );
        break;
      default:
        console.log("Unimplemented");
    }
  }
  console.log();
}

async function newOffer(contract, base_sym, quote_sym, wants, gives) {
  function getAddress(sym) {
    switch (sym) {
      case "WETH":
        return wethAddress;
      default:
        return daiAddress;
    }
  }
  base = getAddress(base_sym);
  quote = getAddress(quote_sym);
  offerTx = await contract.newOffer(
    base,
    quote,
    wants,
    gives,
    ethers.constants.MaxUint256,
    ethers.constants.MaxUint256,
    ethers.constants.MaxUint256
  );
  await offerTx.wait();
  console.log(
    "\t \x1b[44m\x1b[37m OFFER \x1b[0m[\x1b[32m" +
      formatToken(wants, base_sym) +
      base_sym +
      "\x1b[0m | \x1b[31m" +
      formatToken(gives, quote_sym) +
      quote_sym +
      "\x1b[0m]"
  );
}

async function snipe(mgv, base_sym, quote_sym, offerId, wants, gives) {
  function getAddress(sym) {
    switch (sym) {
      case "WETH":
        return wethAddress;
      default:
        return daiAddress;
    }
  }
  base = getAddress(base_sym);
  quote = getAddress(quote_sym);

  snipeTx = await mgv.snipe(
    base,
    quote,
    offerId,
    wants,
    gives,
    ethers.constants.MaxUint256, // max gas
    true //fillWants
  );
  receipt = await snipeTx.wait(0);
  //    console.log(receipt.gasUsed.toString());

  console.log(
    "\t \x1b[44m\x1b[37m TAKE \x1b[0m[\x1b[32m" +
      formatToken(wants, base_sym) +
      base_sym +
      "\x1b[0m | \x1b[31m" +
      formatToken(gives, quote_sym) +
      quote_sym +
      "\x1b[0m]"
  );
}

// describe("Access to compound", function() {
//     it("Should access comptroller implementation", async function () {
//         let oracle = await comp.oracle();
//         assert(oracle != ethers.constants.AddressZero, "Could not access oracle implementaion");
//     })
// });

async function setDecimals() {
  decimals.set("DAI", await dai.decimals());
  decimals.set("ETH", 18);
  decimals.set("WETH", await weth.decimals());
  decimals.set("cETH", await cEth.decimals());
  decimals.set("cDAI", await cDai.decimals());
}

function parseToken(amount, symbol) {
  return ethers.utils.parseUnits(amount, decimals.get(symbol));
}
function formatToken(amount, symbol) {
  return ethers.utils.formatUnits(amount, decimals.get(symbol));
}

describe("Deploy strategies", function () {
  this.timeout(100_000); // Deployment is slow so timeout is increased
  testSigner = null;
  testRunner = null;
  mgv = null;

  before(async function () {
    // 1. mint (1000 dai, 1000 eth, 1000 weth) for owner
    // 2. activates (dai,weth) market
    [testSigner] = await ethers.getSigners();
    testRunner = testSigner.address;
    bal = await testSigner.getBalance();
    await setDecimals();

    await fund([
      ["ETH", "1.0", daiAdmin],
      ["ETH", "1000.0", testRunner],
      ["WETH", "5.0", testRunner],
      ["DAI", "10000.0", testRunner],
    ]);

    let daiBal = await dai.balanceOf(testRunner);
    let wethBal = await weth.balanceOf(testRunner);

    assertEqualBN(daiBal, parseToken("10000.0", "DAI"));
    assertEqualBN(wethBal, parseToken("5.0", "WETH"), "Minting WETH failed");

    mgv = await deployMangrove();
    let cfg = await mgv.callStatic.getConfig(daiAddress, wethAddress);
    assert(cfg.local.active, "Market is inactive");
  });

  // it("should deploy simple strategy", async function () {

  //     const MangroveOffer = await ethers.getContractFactory("MangroveOffer");
  //     const makerContract = await MangroveOffer.deploy(mgv.address);
  //     await makerContract.deployed();

  //     let overrides = {value:parseToken("1.0", 'ETH')};

  //     // testRunner provisions Mangrove for makerContract's bounty
  //     await mgv["fund(address)"](makerContract.address,overrides);
  //     assertEqualBN(
  //         await mgv.balanceOf(makerContract.address),
  //         parseToken("1.0",'ETH'),
  //         "Failed to fund the Mangrove"
  //     );

  //     // cheat to retrieve next assigned offer ID for the next newOffer
  //     offerId = await nextOfferId(daiAddress,wethAddress,makerContract);

  //     // posting new offer on Mngrove via the MakerContract `post` method
  //     await newOffer(
  //         makerContract,
  //         'DAI',
  //         'WETH',
  //         parseToken("1000.0", 'DAI'),
  //         parseToken("0.5", 'WETH'),
  //     );
  //     //await postTx.wait();

  //     [offer, ] = await mgv.offerInfo(daiAddress, wethAddress, offerId);
  //     assertEqualBN(
  //         offer.gives,
  //         parseToken("1000.0", 'DAI'),
  //         "Offer not correctly inserted"
  //     );
  // });

  it("Pure lender strat", async function () {
    const SimpleRetail = await ethers.getContractFactory("SimpleRetail");
    const makerContract = await SimpleRetail.deploy(
      comp.address,
      mgv.address,
      wethAddress
    );
    await makerContract.deployed();

    let overrides = { value: parseToken("1.0", "ETH") };
    tx = await mgv["fund(address)"](makerContract.address, overrides);
    await tx.wait();

    assertEqualBN(
      await mgv.balanceOf(makerContract.address),
      parseToken("1.0", "ETH"),
      "Failed to fund the Mangrove"
    );

    /*********************** TAKER SIDE PREMICES **************************/

    // owner approves Mangrove for WETH before trying to take offer
    tkrTx = await weth
      .connect(owner)
      .approve(mgv.address, ethers.constants.MaxUint256);
    await tkrTx.wait();

    allowed = await weth.allowance(owner.address, mgv.address);
    assertEqualBN(allowed, ethers.constants.MaxUint256, "Approve failed");

    /***********************************************************************/

    /*********************** MAKER SIDE PREMICES **************************/
    const mkrTxs = [];
    let i = 0;
    // offer should get/put base/quote tokens on compound (OK since `owner` is MakerContract admin)
    mkrTxs[i++] = await makerContract
      .connect(owner)
      .enterMarkets([cEthAddress, cDaiAddress]);
    // owner asks MakerContract to approve Mangrove for base (DAI)
    mkrTxs[i++] = await makerContract
      .connect(owner)
      .approveMangrove(daiAddress, ethers.constants.MaxUint256);
    // One sends 1000 DAI to MakerContract
    mkrTxs[i++] = await dai
      .connect(owner)
      .transfer(makerContract.address, parseToken("1000.0", "DAI"));
    // owner asks makerContract to approve cDai to be able to mint cDAI
    mkrTxs[i++] = await makerContract
      .connect(owner)
      .approveCToken(cDai.address, ethers.constants.MaxUint256);
    // makerContract deposits some DAI on Compound (remains 100 DAIs on the contract)
    mkrTxs[i++] = await makerContract
      .connect(owner)
      .mintCToken(cDai.address, parseToken("900.0", "DAI"));

    await synch(mkrTxs);
    /***********************************************************************/
    //console.log("here 1");

    accrueTx = await cDai.connect(owner).accrueInterest();
    receipt = await accrueTx.wait(0);

    await logCompoundStatus(makerContract, ["WETH", "DAI"]);
    // cheat to retrieve next assigned offer ID for the next newOffer
    offerId = await nextOfferId(daiAddress, wethAddress, makerContract);

    // // posting new offer on Mangrove via the MakerContract `post` method
    await newOffer(
      makerContract,
      "DAI",
      "WETH",
      parseToken("1000.0", "DAI"), // promised DAI
      parseToken("0.5", "WETH") // required WETH
    );

    [offer] = await mgv.offerInfo(daiAddress, wethAddress, offerId);
    assertEqualBN(
      offer.gives,
      parseToken("1000.0", "DAI"),
      "Offer not correctly inserted"
    );

    // dry running snipe buy order first
    [success, takerGot, takerGave] = await mgv.callStatic.snipe(
      daiAddress, // maker base
      wethAddress, // maker quote
      offerId,
      parseToken("800.0", "DAI"), // taker wants 800 DAI (takes 0.1 from contract and 0.7 from compound)
      parseToken("0.5", "WETH"), // taker is ready to give up-to 0.5 WETH will give 0.4 WETH
      ethers.constants.MaxUint256, // max gas
      true //fillWants
    );

    assert(success, "Snipe failed");
    assertEqualBN(
      takerGot,
      netOf(parseToken("800.0", "DAI"), fee),
      "Incorrect received amount"
    );
    assertEqualBN(
      takerGave,
      parseToken("0.4", "WETH"),
      "Incorrect given amount"
    );

    await snipe(
      mgv,
      "DAI", // maker base
      "WETH", // maker quote
      offerId,
      parseToken("800.0", "DAI"), // taker wants 0.8 DAI
      parseToken("0.5", "WETH") // taker is ready to give up-to 0.5 WETH
    );

    /// testing status of makerContract's compound pools.
    balEthComp = await cEth
      .connect(owner)
      .callStatic.balanceOfUnderlying(makerContract.address);
    balDaiComp = await cDai
      .connect(owner)
      .callStatic.balanceOfUnderlying(makerContract.address);

    // checking that MakerContract did put received WETH on compound (as cETH) --allowing 5 gwei of rounding error
    assertAlmost(takerGave, balEthComp, 9, "Incorrect Eth amount on Compound");
    // checking that MakerContract did get 0.7 ethers of DAI from compound (= 0.8 - 0.1 from contract provision)
    // maker gave 800, taking 100 directly from MakerContract and 700 from compound
    // remaining balance on compound should be ~ 200
    expected = parseToken("200", "DAI");
    assertAlmost(expected, balDaiComp, 4, "Incorrect Dai amount on Compound");

    accrueTx = await cDai.connect(owner).accrueInterest();
    receipt = await accrueTx.wait(0);

    await logCompoundStatus(makerContract, ["WETH", "DAI"]);
  });

  it("Lender/borrower strat", async function () {
    const AdvancedRetail = await ethers.getContractFactory("AdvancedRetail");
    const makerContract = await AdvancedRetail.deploy(
      comp.address,
      mgv.address,
      wethAddress
    );
    await makerContract.deployed();

    let overrides = { value: parseToken("10.0", "ETH") };
    tx = await mgv["fund(address)"](makerContract.address, overrides);
    await tx.wait();

    /*********************** MAKER SIDE PREMICES **************************/
    const mkrTxs = [];
    let i = 0;
    mkrTxs[i++] = await makerContract
      .connect(owner)
      .enterMarkets([cEthAddress, cDaiAddress]);
    // owner asks MakerContract to approve Mangrove for base (DAI)
    mkrTxs[i++] = await makerContract
      .connect(owner)
      .approveMangrove(daiAddress, ethers.constants.MaxUint256);
    // owner provisions MakerContract with DAI
    mkrTxs[i++] = await dai
      .connect(owner)
      .transfer(makerContract.address, parseToken("250.0", "DAI"));
    // owner asks makerContract to approve cDai to be able to mint cDAI
    mkrTxs[i++] = await makerContract
      .connect(owner)
      .approveCToken(cDai.address, ethers.constants.MaxUint256);
    // makerContract deposits some DAI on Compound (remains 100 DAIs on the contract)
    mkrTxs[i++] = await makerContract
      .connect(owner)
      .mintCToken(cDai.address, parseToken("200", "DAI"));

    await synch(mkrTxs);

    /***********************************************************************/

    accrueTx = await cDai.connect(owner).accrueInterest();
    receipt = await accrueTx.wait(0);

    await logCompoundStatus(makerContract, ["WETH", "DAI"]);
    // cheat to retrieve next assigned offer ID for the next newOffer
    offerId = await nextOfferId(daiAddress, wethAddress, makerContract);

    // // posting new offer on Mangrove via the MakerContract `post` method
    await newOffer(
      makerContract,
      "DAI",
      "WETH",
      parseToken("300.0", "DAI"), // promised DAI (will need to borrow)
      parseToken("0.15", "WETH") // required WETH
    );

    [offer] = await mgv.offerInfo(daiAddress, wethAddress, offerId);
    assertEqualBN(
      offer.gives,
      parseToken("300.0", "DAI"),
      "Offer not correctly inserted"
    );

    // dry running snipe buy order first
    [success, takerGot, takerGave] = await mgv.callStatic.snipe(
      daiAddress, // maker base
      wethAddress, // maker quote
      offerId,
      parseToken("300", "DAI"),
      parseToken("0.15", "WETH"),
      ethers.constants.MaxUint256, // max gas
      true //fillWants
    );

    assert(success, "Snipe failed");
    assertEqualBN(
      takerGot,
      netOf(parseToken("300", "DAI"), fee),
      "Incorrect received amount"
    );
    assertEqualBN(
      takerGave,
      parseToken("0.15", "WETH"),
      "Incorrect given amount"
    );

    await snipe(
      mgv,
      "DAI", // maker base
      "WETH", // maker quote
      offerId,
      parseToken("300", "DAI"),
      parseToken("0.15", "WETH")
    );

    await snipeTx.wait();

    /// testing status of makerContract's compound pools.
    balEthComp = await cEth
      .connect(owner)
      .callStatic.balanceOfUnderlying(makerContract.address);
    balDaiComp = await cDai
      .connect(owner)
      .callStatic.balanceOfUnderlying(makerContract.address);

    // checking that MakerContract did put received WETH on compound (as cETH) --allowing 5 gwei of rounding error
    assertAlmost(takerGave, balEthComp, 8, "Incorrect Eth amount on Compound");
    // checking that MakerContract did get 0.7 ethers of DAI from compound (= 0.8 - 0.1 from contract provision)
    // maker gave 800, taking 100 directly from MakerContract and 700 from compound
    // remaining balance on compound should be ~ 200
    assertAlmost(
      balDaiComp,
      balDaiComp,
      4,
      "Incorrect Dai amount on Compound " + formatToken(balDaiComp, "DAI")
    );

    accrueTx = await cDai.connect(owner).accrueInterest();
    receipt = await accrueTx.wait(0);

    await logCompoundStatus(makerContract, ["WETH", "DAI"]);
    offerId = await nextOfferId(wethAddress, daiAddress, makerContract);

    // owner asks MakerContract to approve Mangrove for base (weth)
    mkrTx2 = await makerContract
      .connect(owner)
      .approveMangrove(wethAddress, ethers.constants.MaxUint256);
    await mkrTx2.wait();

    await newOffer(
      makerContract,
      "WETH",
      "DAI",
      parseToken("0.2", "WETH"), // promised WETH
      parseToken("380.0", "DAI") // required DAI
    );

    // taker approves mgv for DAI erc
    tkrTx = await dai
      .connect(owner)
      .approve(mgv.address, ethers.constants.MaxUint256);
    await tkrTx.wait();

    await snipe(
      mgv,
      "WETH",
      "DAI",
      offerId,
      parseToken("0.2", "WETH"), // wanted WETH
      parseToken("380.0", "DAI") // giving DAI
    );
    await logCompoundStatus(makerContract, ["WETH", "DAI"]);
  });
});
