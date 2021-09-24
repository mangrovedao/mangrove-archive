const { ethers, env, mangrove, network } = require("hardhat");
const config = require("config");
const { assert } = require("chai");
const provider = ethers.provider;
const chalk = require("chalk");

async function fund(funding_tuples) {
  async function mintNative(recipient, amount) {
    await network.provider.send("hardhat_setBalance", [
      recipient,
      ethers.utils.hexValue(amount), // not amount.toHexString() which would be zero padded!
    ]);
  }

  async function mintPolygonChildErc(contract, recipient, amount) {
    let chainMgr = env.mainnet.childChainManager;
    let amount_bytes = ethers.utils.hexZeroPad(amount, 32);
    let admin_signer = provider.getSigner(chainMgr);
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [chainMgr],
    });
    if ((await admin_signer.getBalance()).eq(0)) {
      await mintNative(chainMgr, parseToken("1.0", 18));
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
        let dai = await getContract("DAI");
        amount = parseToken(amount, 18);
        if (env.mainnet.name == "ethereum") {
          let daiAdmin = env.mainnet.tokens.dai.admin;
          await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [daiAdmin],
          });
          let admin_signer = provider.getSigner(daiAdmin);
          if ((await admin_signer.getBalance()).eq(0)) {
            await mintNative(daiAdmin, parseToken("1.0", 18));
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
        } else {
          console.warn(`Unknown network ${env.mainnet.name}`);
        }
      }
      case "WETH": {
        let wEth = await getContract("WETH");
        amount = parseToken(amount, await getDecimals("WETH"));

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
        if (env.mainnet.name == "polygon") {
          await mintPolygonChildErc(wEth, recipient, amount);
          break;
        } else {
          console.warn("Unknown network");
        }
      }
      case "ETH":
      case "MATIC": {
        amount = parseToken(amount, 18);
        await mintNative(recipient, amount);
        break;
      }
      default: {
        console.warn("Not implemented ERC funding method: ", token_symbol);
      }
    }
  }
}

function getUnderlyingSymbol(symbol) {
  switch (symbol) {
    case "CDAI":
    case "CETH":
    case "ADAI":
    case "AWETH":
      return symbol.slice(1, symbol.length);
    default:
      console.warn(`${symbol} is not a recognized overlying symbol`);
  }
}
async function getContract(symbol) {
  let net = env.mainnet;
  switch (symbol) {
    case "DAI":
      return net.tokens.dai.contract;
    case "CDAI":
      return net.tokens.cDai.contract;
    case "WETH":
      return net.tokens.wEth.contract;
    case "CWETH":
      return net.tokens.cwEth.contract;
    case "ADAI":
    case "AWETH": {
      const underlying = await getContract(getUnderlyingSymbol(symbol));
      const aTokenAddress = (
        await net.aave.lendingPool.getReserveData(underlying.address)
      ).aTokenAddress;
      const aToken = new ethers.Contract(
        aTokenAddress,
        net.abis.aToken,
        ethers.provider
      );
      return aToken;
    }
    case "WETH":
      return net.tokens.wEth.contract;
    case "AAVE":
      return net.aave.addressesProvider;
    case "COMP":
      return net.compound.contract;
    default:
      console.warn("Unhandled contract symbol: ", symbol);
  }
}

async function getDecimals(symbol) {
  switch (symbol) {
    case "MATIC":
    case "ETH":
      return 18;
    case "DAI":
    case "WETH":
    case "CDAI":
    case "ADAI":
    case "CWETH":
    case "AWETH":
      const token = await getContract(symbol);
      return await token.decimals();
  }
}

function getOverlyingSymbol(symbol, lenderName) {
  if (lenderName == "compound") {
    return "C" + symbol;
  }
  if (lenderName == "aave") {
    return "A" + symbol;
  }
}

function getCompoundToken(symbol) {
  switch (symbol) {
    case "DAI":
      return env.mainnet.tokens.cDai.contract;
    case "WETH":
      return env.mainnet.tokens.cwEth.contract;
    default:
      console.warn("No compound token for: ", symbol);
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
    parseToken("1.0", 18),
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

async function logLenderStatus(contract, lenderName, tokens) {
  async function getAaveBorrowBalance(symbol) {
    const pool = env.mainnet.aave.lendingPool;
    const token = await getContract(symbol);
    const reserveData = await pool.getReserveData(token.address);
    const stableDebtTokenAddress = reserveData.stableDebtTokenAddress;
    const variableDebtTokenAddress = reserveData.variableDebtTokenAddress;
    const stableDebt = new ethers.Contract(
      stableDebtTokenAddress,
      env.mainnet.abis.stableDebtToken,
      ethers.provider
    );
    const variableDebt = new ethers.Contract(
      variableDebtTokenAddress,
      env.mainnet.abis.variableDebtToken,
      ethers.provider
    );
    const sbalance = await stableDebt.balanceOf(contract.address);
    const vbalance = await variableDebt.balanceOf(contract.address);
    return [sbalance, vbalance];
  }
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

  let baseUnit;
  let borrowPower;
  let compound = await getContract("COMP");
  let pool = env.mainnet.aave.lendingPool;

  if (lenderName == "compound") {
    baseUnit = "USD";
    [, borrowPower] = await compound.getAccountLiquidity(contract.address);
  }
  if (lenderName == "aave") {
    baseUnit = "ETH";
    [, , borrowPower, , ,] = await pool.getUserAccountData(contract.address);
  }
  //console.log(borrowPower,lenderName);
  console.log(
    `**** ${lenderName} borrow power (${baseUnit}): \x1b[35m`,
    formatToken(borrowPower, 18),
    "\x1b[0m ****"
  );
  for (const symbol of tokens) {
    switch (lenderName) {
      case "compound": {
        const cToken = getCompoundToken(symbol);
        const [, , borrowBalance] = await cToken.getAccountSnapshot(
          contract.address
        );
        const token = await getContract(symbol);
        const [redeemable] = await contract.maxGettableUnderlying(
          cToken.address
        );
        const balance = await token.balanceOf(contract.address);
        const decimals = await getDecimals(symbol);
        logPosition(
          symbol,
          formatToken(redeemable, decimals),
          formatToken(borrowBalance, decimals),
          formatToken(balance, decimals)
        );
        break;
      }
      case "aave": {
        const decimals = await getDecimals(symbol);
        const token = await getContract(symbol);
        const [stableBorrowBalance, variableBorrowBalance] =
          await getAaveBorrowBalance(symbol);
        const borrowBalanceStr =
          formatToken(stableBorrowBalance, decimals) +
          "/" +
          formatToken(variableBorrowBalance, decimals);
        const [redeemable] = await contract.maxGettableUnderlying(
          token.address
        );
        const balance = await token.balanceOf(contract.address);

        logPosition(
          symbol,
          formatToken(redeemable, decimals),
          borrowBalanceStr,
          formatToken(balance, decimals)
        );
        break;
      }
      default:
        console.warn("Unrecognized lender ", lenderName);
    }
  }
  console.log();
}

async function newOffer(mgv, contract, base_sym, quote_sym, wants, gives) {
  const base = await getContract(base_sym);
  const quote = await getContract(quote_sym);

  const offerId = await nextOfferId(base.address, quote.address, contract);
  const offerTx = await contract.newOffer(
    base.address,
    quote.address,
    wants,
    gives,
    ethers.constants.MaxUint256,
    ethers.constants.MaxUint256,
    ethers.constants.MaxUint256
  );
  await offerTx.wait();
  const book = await mgv.reader.book(base.address, quote.address, 2);
  await logOrderBook(book, base, quote);

  return offerId;
}

async function snipeSuccess(mgv, base_sym, quote_sym, offerId, wants, gives) {
  const base = await getContract(base_sym);
  const quote = await getContract(quote_sym);

  const [success, takerGot, takerGave] = await mgv.callStatic.snipe(
    base.address,
    quote.address,
    offerId,
    wants, // wanted WETH
    gives, // giving DAI
    ethers.constants.MaxUint256, // max gas
    true
  );

  assert(success, "Snipe failed");

  const snipeTx = await mgv.snipe(
    base.address,
    quote.address,
    offerId,
    wants,
    gives,
    ethers.constants.MaxUint256, // max gas
    true //fillWants
  );
  await snipeTx.wait(0);

  console.log(
    "\t",
    chalk.bgGreen.black("ORDER FULFILLED"),
    "[",
    chalk.green(formatToken(wants, await getDecimals(base_sym)) + base_sym),
    " | ",
    chalk.red(formatToken(gives, await getDecimals(quote_sym)) + quote_sym),
    "]\n"
  );
  const book = await mgv.reader.book(base.address, quote.address, 2);
  await logOrderBook(book, base, quote);
  return [takerGot, takerGave];
}

async function snipeFail(mgv, base_sym, quote_sym, offerId, wants, gives) {
  const base = await getContract(base_sym);
  const quote = await getContract(quote_sym);

  const [success, ,] = await mgv.callStatic.snipe(
    base.address,
    quote.address,
    offerId,
    wants, // wanted WETH
    gives, // giving DAI
    ethers.constants.MaxUint256, // max gas
    true
  );

  assert(!success, "Snipe should fail");

  snipeTx = await mgv.snipe(
    base.address,
    quote.address,
    offerId,
    wants,
    gives,
    ethers.constants.MaxUint256, // max gas
    true //fillWants
  );
  console.log(
    "\t",
    chalk.bgRed.white("ORDER RENEGED"),
    "[",
    chalk.green(formatToken(wants, await getDecimals(base_sym)) + base_sym),
    " | ",
    chalk.red(formatToken(gives, await getDecimals(quote_sym)) + quote_sym),
    "]\n"
  );
  await snipeTx.wait(0);
  const book = await mgv.reader.book(base.address, quote.address, 2);
  await logOrderBook(book, base, quote);
  // console.log(receipt.gasUsed.toString());
}

async function deployMangrove() {
  const Mangrove = await ethers.getContractFactory("Mangrove");
  const MangroveReader = await ethers.getContractFactory("MgvReader");

  const mgv_gasprice = 500;
  let gasmax = 2000000;
  const deployer = await provider.getSigner().getAddress();
  const mgv = await Mangrove.deploy(deployer, mgv_gasprice, gasmax);
  await mgv.deployed();
  const receipt = await mgv.deployTransaction.wait(0);
  console.log(
    "Mangrove deployed (" + receipt.gasUsed.toString() + " gas used)"
  );
  const mgvReader = await MangroveReader.deploy(mgv.address);
  await mgvReader.deployed();
  mgv.reader = mgvReader;
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

function parseToken(amount, decimals) {
  return ethers.utils.parseUnits(amount, decimals);
}

function formatToken(amount, decimals) {
  return ethers.utils.formatUnits(amount, decimals);
}

async function expectAmountOnLender(makerContract, lenderName, expectations) {
  for (const [symbol_underlying, expected_amount, precision] of expectations) {
    const overlying = await getContract(
      getOverlyingSymbol(symbol_underlying, lenderName)
    );
    let balance;
    switch (lenderName) {
      case "compound":
        balance = await overlying.callStatic.balanceOfUnderlying(
          makerContract.address
        );
        break;
      case "aave":
        balance = await overlying.balanceOf(makerContract.address);
        break;
      default:
        console.warn("Lender is not recognized");
    }
    assertAlmost(
      expected_amount,
      balance,
      precision,
      `Incorrect ${symbol_underlying} amount on ${lenderName}`
    );
  }
}

async function logOrderBook([offerIds, offers], base, quote) {
  const bd = await base.decimals();
  const qd = await quote.decimals();
  const bs = await base.symbol();
  const qs = await quote.symbol();
  console.log(chalk.black.bgBlue(`====(${bs},${qs})====`));
  let cpt = 0;
  offerIds.forEach((offerId, i) => {
    if (offerId != 0) {
      cpt++;
      const offer = offers[i];
      console.log(
        chalk.blue(offerId.toString()),
        ":",
        formatToken(offer.gives, qd),
        formatToken(offer.wants, bd)
      );
    }
  });
  if (cpt == 0) {
    console.log(chalk.blue("\u2205"));
  }
  console.log();
}

exports.logOrderBook = logOrderBook;
exports.getDecimals = getDecimals;
exports.parseToken = parseToken;
exports.formatToken = formatToken;
exports.assertAlmost = assertAlmost;
exports.assertEqualBN = assertEqualBN;
exports.synch = synch;
exports.logLenderStatus = logLenderStatus;

// calls to makerContract (will forward to mangrove)
exports.snipeSuccess = snipeSuccess;
exports.snipeFail = snipeFail;

exports.newOffer = newOffer;

// returns nextOfferId in mangrove
exports.nextOfferId = nextOfferId;

// returns amount minus takerfees
exports.netOf = netOf;

//deploys mangrove
exports.deployMangrove = deployMangrove;

// activates a market on mangrove with presets
exports.activateMarket = activateMarket;

// getContract : "[a|c]WETH" | "[a|c]DAI" | "COMP" | "AAVE" -> contract obj
exports.getContract = getContract;

// fund : (token_symbol, amount_string, recipient) array -> unit
// ex. fund([["DAI", "100.4", 0xabcd],["ETH","1",0xabcd]]) will credit the 0xabcd account with 100.4 DAIs and 1 native gas token (ether or matic)
exports.fund = fund;

// expectAmountOnLender : (user:address, lenderName:["compound | aave"], expectations:(symbol_underlying:string, expected_amount:bigNumber, precision:uint) array -> unit
// ex. expectAmountOnLender(0xabcd,"compound",[["WETH",amount_w,8],["DAI",amount_dai,4]])
// checks if user 0xabcd had amount_w (with 4 decimals precision) weth and amount_dai (with 4 decimals precision) as collateral on compoound
exports.expectAmountOnLender = expectAmountOnLender;
