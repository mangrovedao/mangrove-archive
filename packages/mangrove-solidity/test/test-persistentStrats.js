const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers, env, mangrove, network } = require("hardhat");
const lc = require("../lib/libcommon.js");
const chalk = require("chalk");

let testSigner = null;

describe("Running tests...", function () {
  this.timeout(100_000); // Deployment is slow so timeout is increased
  let mgv = null;
  let dai = null;
  let usdc = null;
  let wEth = null;
  let cwEth = null;
  let cDai = null;
  let cUsdc = null;

  before(async function () {
    // 1. mint (1000 dai, 1000 eth, 1000 weth) for testSigner
    // 2. activates (dai,weth) market
    dai = await lc.getContract("DAI");
    wEth = await lc.getContract("WETH");
    usdc = await lc.getContract("USDC");
    cwEth = await lc.getContract("CWETH");
    cUsdc = await lc.getContract("CUSDC");
    cDai = await lc.getContract("CDAI");

    [testSigner] = await ethers.getSigners();

    await lc.fund([
      ["ETH", "10000.0", testSigner.address],
      ["WETH", "1000.0", testSigner.address],
      ["USDC", "1000000.0", testSigner.address],
      //      ["DAI", "10000.0", testSigner.address]
    ]);

    mgv = await lc.deployMangrove();
    await lc.activateMarket(mgv, dai.address, wEth.address);
    await lc.activateMarket(mgv, dai.address, usdc.address);
    await lc.activateMarket(mgv, wEth.address, usdc.address);
  });

  it("Swinging strat", async function () {
    const strategy = "SwingingMarketMaker";
    const Strat = await ethers.getContractFactory(strategy);
    const comp = await lc.getContract("COMP");

    // deploying strat
    const makerContract = await Strat.deploy(
      comp.address,
      mgv.address,
      wEth.address
    );
    const eth_for_one_usdc = lc.parseToken("0.0004", 18); // 1/2500 ethers
    const usdc_for_one_eth = lc.parseToken("2510", 6); // 2510 $

    await makerContract
      .connect(testSigner)
      .setPrice(wEth.address, usdc.address, eth_for_one_usdc);
    await makerContract
      .connect(testSigner)
      .setPrice(usdc.address, wEth.address, usdc_for_one_eth);

    await lc.fund([
      ["ETH", "1.0", makerContract.address], // sending gas to makerContract
      ["DAI", "100000.0", makerContract.address], // sending DAIs to makerContract
    ]);
    await wEth
      .connect(testSigner)
      .approve(mgv.address, ethers.constants.MaxUint256);
    await usdc
      .connect(testSigner)
      .approve(mgv.address, ethers.constants.MaxUint256);
    await dai
      .connect(testSigner)
      .approve(mgv.address, ethers.constants.MaxUint256);

    let overrides = { value: lc.parseToken("2.0", 18) };
    const tx = await mgv["fund(address)"](makerContract.address, overrides);
    await tx.wait();

    const amount = lc.parseToken("1000.0", 6);

    await makerContract
      .connect(testSigner)
      .startStrat(usdc.address, wEth.address, amount); // gives 1000 $

    // putting dai on compound
    await makerContract
      .connect(testSigner)
      .approveLender(cwEth.address, ethers.constants.MaxUint256);
    await makerContract
      .connect(testSigner)
      .approveLender(cUsdc.address, ethers.constants.MaxUint256);
    await makerContract
      .connect(testSigner)
      .approveLender(cDai.address, ethers.constants.MaxUint256);

    await makerContract.connect(testSigner).enterMarkets([cwEth.address]);
    await makerContract.connect(testSigner).enterMarkets([cUsdc.address]);
    await makerContract.connect(testSigner).enterMarkets([cDai.address]);

    const daiAmount = lc.parseToken("100000.0", 18);
    await makerContract.connect(testSigner).mint(cDai.address, daiAmount);

    await lc.logLenderStatus(makerContract, "compound", ["WETH"]);

    for (let i = 0; i < 10; i++) {
      let book01 = await mgv.reader.book(usdc.address, wEth.address, 0, 1);
      let book10 = await mgv.reader.book(wEth.address, usdc.address, 0, 1);
      await lc.logOrderBook(book01, usdc, wEth);
      await lc.logOrderBook(book10, wEth, usdc);

      // market order
      let takerGot;
      let takerGave;
      if (i % 2 == 0) {
        [takerGot, takerGave] = await lc.marketOrder(
          mgv,
          "USDC",
          "WETH",
          lc.parseToken("1000", await usdc.decimals()), //takerWants
          lc.parseToken("1.0", 18) //takerGives
        );
        console.log(
          chalk.green(lc.formatToken(takerGot, 6)),
          chalk.red(lc.formatToken(takerGave, 18))
        );
      } else {
        [takerGot, takerGave] = await lc.marketOrder(
          mgv,
          "WETH",
          "USDC",
          lc.parseToken("0.4", 18), //takerWants
          lc.parseToken("2000", await usdc.decimals()) //takerGives
        );
        console.log(
          chalk.green(lc.formatToken(takerGot, 18)),
          chalk.red(lc.formatToken(takerGave, 6))
        );
      }
    }
    await lc.logLenderStatus(makerContract, "compound", ["USDC", "WETH"]);
  });
});

// const usdc_decimals = await usdc.decimals();
// const filter_PosthookFail = mgv.filters.PosthookFail();
// mgv.once(filter_PosthookFail, (
//   outbound_tkn,
//   inbound_tkn,
//   offerId,
//   makerData,
//   event) => {
//     let outSym;
//     let inSym;
//     if (outbound_tkn == wEth.address) {
//       outSym = "WETH";
//       inSym = "USDC";
//     } else {
//       outSym = "USDC";
//       inSym = "WETH";
//     }
//     console.log(`Failed to repost offer #${offerId} on (${outSym},${inSym}) Offer List`);
//     console.log(ethers.utils.parseBytes32String(makerData));
//   }
// );
// const filter_MangroveFail = mgv.filters.OfferFail();
// mgv.once(filter_MangroveFail, (
//   outbound_tkn,
//   inbound_tkn,
//   offerId,
//   taker_address,
//   takerWants,
//   takerGives,
//   statusCode,
//   makerData,
//   event
//   ) => {
//     let outDecimals;
//     let inDecimals;
//     if (outbound_tkn == wEth.address) {
//       outDecimals = 18;
//       inDecimals = usdc_decimals;
//     } else {
//       outTkn = usdc_decimals;
//       inTkn = 18;
//     }
//   console.warn("Contract failed to execute taker order. Offer was: ", outbound_tkn, inbound_tkn, offerId);
//   console.warn("Order was ",
//   lc.formatToken(takerWants, outDecimals),
//   lc.formatToken(takerGives, inDecimals)
//   );
//   console.warn(ethers.utils.parseBytes32String(statusCode));
// });
// const filterContractLiquidity = makerContract.filters.NotEnoughLiquidity();
// makerContract.once(filterContractLiquidity, (outbound_tkn, missing, event) => {
//   let outDecimals;
//   let symbol;
//   if (outbound_tkn == wEth.address) {
//     outDecimals = 18;
//     symbol = "WETH";
//   } else {outDecimals = usdc_decimals; symbol = "USDC";}
//   console.warn ("could not fetch ",lc.formatToken(missing,outDecimals),symbol);
// }
// );

// const filterContractRepay = makerContract.filters.ErrorOnRepay();
// makerContract.once(filterContractRepay, (inbound_tkn, toRepay, errCode, event) => {
//   let inDecimals;
//   let symbol;
//   if (inbound_tkn == wEth.address) {
//     inDecimals = 18;
//     symbol = "WETH";
//   } else {inDecimals = usdc_decimals; symbol = "USDC";}
//   console.warn ("could not repay ",lc.formatToken(toRepay,inDecimals),symbol);
//   console.warn (errCode.toString());
// });
