const { ethers, env, mangrove, network } = require("hardhat");
const config = require("config");
const { assert } = require("chai");

const decimals = new Map();

let { dai, cDai, wEth, cwEth, comp } = {};
if (config.has("polygon")) {
  dai = env.polygon.tokens.dai.contract;
  cDai = env.polygon.tokens.crDai.contract;
  wEth = env.polygon.tokens.wEth.contract;
  cwEth = env.polygon.tokens.crWeth.contract;
  comp = env.polygon.compound.contract;
}
if (config.has("ethereum")) {
  dai = env.ethereum.tokens.dai.contract;
  cDai = env.ethereum.tokens.cDai.contract;
  wEth = env.ethereum.tokens.wEth.contract;
  cwEth = env.ethereum.tokens.cEth.contract;
  comp = env.ethereum.compound.contract;
}

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
        [, redeemableDai] = await contract.maxGettableUnderlying(cDai.address);
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
        [, redeemableWeth] = await contract.maxGettableUnderlying(
          cwEth.address
        );
        [, , borrowBalance] = await cwEth.getAccountSnapshot(contract.address);
        wethBalance = await wEth.balanceOf(contract.address);
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
        return wEth.address;
      default:
        return dai.address;
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
        return wEth.address;
      default:
        return dai.address;
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

async function deployMangrove() {
  const Mangrove = await ethers.getContractFactory("Mangrove");
  const mgv_gasprice = 500;
  let gasmax = 2000000;
  const mgv = await Mangrove.deploy(mgv_gasprice, gasmax);
  await mgv.deployed();
  const receipt = await mgv.deployTransaction.wait(0);
  console.log(
    "Mangrove deployed (" + receipt.gasUsed.toString() + " gas used)"
  );
  return mgv;
}

async function activateMarket(mgv, aTokenAddress, bTokenAddress) {
  fee = 30; // setting fees to 0.03%
  density = 10000;
  overhead_gasbase = 20000;
  offer_gasbase = 20000;
  activateTx = await mgv.activate(
    aTokenAddress,
    bTokenAddress,
    fee,
    density,
    overhead_gasbase,
    offer_gasbase
  );
  await activateTx.wait();
  activateTx = await mgv.activate(
    bTokenAddress,
    aTokenAddress,
    fee,
    density,
    overhead_gasbase,
    offer_gasbase
  );
  await activateTx.wait();
}

async function setDecimals() {
  decimals.set("DAI", await dai.decimals());
  decimals.set("ETH", 18);
  decimals.set("MATIC", 18);
  decimals.set("WETH", await wEth.decimals());
  decimals.set("cETH", await cwEth.decimals());
  decimals.set("cDAI", await cDai.decimals());
}

function parseToken(amount, symbol) {
  return ethers.utils.parseUnits(amount, decimals.get(symbol));
}
function formatToken(amount, symbol) {
  return ethers.utils.formatUnits(amount, decimals.get(symbol));
}

exports.setDecimals = setDecimals;
exports.formatToken = formatToken;
exports.parseToken = parseToken;
exports.formatToken = formatToken;
exports.assertAlmost = assertAlmost;
exports.assertEqualBN = assertEqualBN;
exports.synch = synch;
exports.logCompoundStatus = logCompoundStatus;
exports.snipe = snipe;
exports.newOffer = newOffer;
exports.nextOfferId = nextOfferId;
exports.netOf = netOf;
exports.deployMangrove = deployMangrove;
exports.activateMarket = activateMarket;

exports.dai = dai;
exports.cDai = cDai;
exports.wEth = wEth;
exports.cwEth = cwEth;
exports.comp = comp;
