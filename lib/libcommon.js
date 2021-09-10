const { ethers, env, mangrove, network } = require("hardhat");
const config = require("config");
const { assert } = require("chai");

const decimals = new Map();
const provider = ethers.provider;


async function fund(funding_tuples) {

  async function mintNative(recipient, amount) {
    console.log(amount,amount.toHexString(),ethers.utils.hexValue(amount));   
    await network.provider.send("hardhat_setBalance", [
      recipient,
      ethers.utils.hexValue(amount), // not amount.toHexString() which would be zero padded!
    ]);
  }

  async function mintPolygonChildErc(contract, recipient, amount) {
    let chainMgr = env.polygon.admin.childChainManager;
    let amount_bytes = ethers.utils.hexZeroPad(amount, 32);
    let admin_signer = provider.getSigner(chainMgr);
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [chainMgr],
    });
    if ((await admin_signer.getBalance()).eq(0)) {
      await mintNative(chainMgr, parseToken("1.0"));
    }
    let mintTx = await contract
      .connect(admin_signer)
      .deposit(recipient, amount_bytes);
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
    let [signer] = await ethers.getSigners();

    switch (token_symbol) {
      case "DAI": {
        let dai = getContract("DAI");
        let decimals = await dai.decimals();
        console.log("Minting dai's...");
        amount = parseToken(amount, decimals);
        if (env.mainnet.name == "ethereum") {
          let daiAdmin = env.mainnet.tokens.dai.admin;
          await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [daiAdmin],
          });
          let admin_signer = provider.getSigner(daiAdmin);
          if ((await admin_signer.getBalance()).eq(0)) {
            await mintNative(daiAdmin, parseToken("1.0",18));
          }
          let mintTx = await dai.connect(admin_signer).mint(recipient, amount);
          await mintTx.wait();
          await network.provider.request({
            method: "hardhat_stopImpersonatingAccount",
            params: [daiAdmin],
          });
          break;
        }
        if (env.mainnet.name == "polygon") {
          await mintPolygonChildErc(dai, recipient, amount);
          break;
        }
        else {
          console.warn (`Unknown network ${env.mainnet.name}`);
        }
      }
      case "WETH": {
        console.log("Minting wEths...");
        let wEth = getContract("WETH");
        let decimals = await wEth.decimals();
        amount = parseToken(amount,decimals);

        if (env.mainnet.name == "ethereum") {
          if (recipient != signer.address) {
            await network.provider.request({
              method: "hardhat_impersonateAccount",
              params: [recipient],
            });
            signer = provider.getSigner(recipient);
          }
          let bal = await signer.getBalance();
          if (bal.lt(amount)) {
            await mintNative(recipient, amount);
          }
          let mintTx = await wEth.connect(signer).deposit({ value: amount });
          await mintTx.wait();
          if (recipient != signer.address) {
            await network.provider.request({
              method: "hardhat_stopImpersonateAccount",
              params: [recipient],
            });
          }
          break;
        }
        if (env.mainnet.name == "polygon"){
          await mintPolygonChildErc(wEth, recipient, amount);
          break;
        }
        else {
          console.warn ("Unknown network");
        }
      }
      case "ETH": 
      case "MATIC": {
        console.log("Minting gas tokens...");
        
        amount = parseToken(amount,18);
        await mintNative(recipient, amount);
        break;
      }
      default: {
        console.warn("Not implemented ERC funding method: ", token_symbol);
      }
    }
  }
}

function getContract(symbol) {
  let net = env.mainnet;
  switch(symbol) {
    case "DAI" :
      return net.tokens.dai.contract;
    case "CDAI" :
      return net.tokens.cDai.contract;
    case "WETH" :
      return net.tokens.wEth.contract;
    case "CWETH" :
      return net.tokens.cwEth.contract;
    case "AWETH" :
      return net.tokens.awEth.contract;
    case "ADAI" :
      return net.tokens.aDai.contract;
    case "WETH" :
      return net.tokens.wEth.contract;
    case "AAVE_pool" :
      return net.aave.lendingPool;
    case "AAVE_ap" :
      return net.aave.addressProvider;
    case "COMP" :
      return net.compound.contract;
    default:
      console.warn ("Unhandled contract symbol: ", symbol);
  }
}

function assertEqualBN(value1, value2, msg) {
  let errorMsg =
    msg +
    ("(Received: " +
      value1.toString() +
      ", Expected: " +
      value2.toString() +
      ")");
  assert(value1.eq(value2), errorMsg);
}

async function nextOfferId(base, quote, ctr) {
  let offerId = await ctr.callStatic.newOffer(
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

async function logCompoundStatus(contract, tokens) {
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
  const comp = getContract("COMP");
  const cDai = getContract("CDAI");
  const cwEth = getContract("CWETH");
  const wEth = getContract("WETH");
  const dai = getContract("DAI");

  [, liquidity] = await comp.getAccountLiquidity(contract.address);
  console.log();
  console.log(
    "**** Account borrow power (USD): \x1b[35m",
    formatToken(liquidity, 18),
    "\x1b[0m ****"
  );
  for (const symbol of tokens) {
    switch (symbol) {
      case "DAI":
        const [, redeemableDai] = await contract.maxGettableUnderlying(cDai.address);
        const [, , borrowDaiBalance] = await cDai.getAccountSnapshot(contract.address);
        const daiBalance = await dai.balanceOf(contract.address);
        logPosition(
          "DAI",
          formatToken(redeemableDai, "DAI"),
          formatToken(borrowDaiBalance, "DAI"),
          formatToken(daiBalance, "DAI")
        );
        break;
      case "WETH":
        const [, redeemableWeth] = await contract.maxGettableUnderlying(
          cwEth.address
        );
        const [, , borrowWethBalance] = await cwEth.getAccountSnapshot(contract.address);
        const wethBalance = await wEth.balanceOf(contract.address);
        logPosition(
          "WETH",
          formatToken(redeemableWeth, "DAI"),
          formatToken(borrowWethBalance, "DAI"),
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
  
  base = getContract(base_sym).address;
  quote = getContract(quote_sym).address;
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
  base = getContract(base_sym).address;
  quote = getContract(quote_sym).address;

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
  for (sym of ["DAI", "WETH", "CWETH", "CDAI"]) {
    decimals.set(sym, await getContract(sym).decimals());
  }
  decimals.set("ETH", 18);
  decimals.set("MATIC", 18);
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
exports.getContract = getContract;
exports.fund = fund;
