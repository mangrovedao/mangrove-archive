const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers, env, mangrove, network } = require("hardhat");
const lc = require("../lib/libcommon.js");
const chalk = require("chalk");

let testSigner = null;

function Big(x) {
  return lc.Big(x);
}

describe("Running tests...", function () {
  this.timeout(200_000); // Deployment is slow so timeout is increased
  let mgv = null;
  let dai = null;
  let usdc = null;

  before(async function () {
    // fetches all token contracts
    dai = await lc.getContract("DAI");
    usdc = await lc.getContract("USDC");
    wEth = await lc.getContract("WETH");

    // setting testRunner signer
    [testSigner] = await ethers.getSigners();

    // deploying mangrove and opening WETH/USDC market.
    mgv = await lc.deployMangrove();
    await lc.activateMarket(mgv, dai.address, usdc.address);
  });

  it("Minting tokens", async function () {
    // mumbai fork comes with a non zero balance of DAI and USDC !
    let daiAmount = await dai.balanceOf(testSigner.address);
    let usdcAmount = await usdc.balanceOf(testSigner.address);
    let wethAmount = await wEth.balanceOf(testSigner.address);

    await lc.fund([
      ["DAI", "1000", testSigner.address],
      ["USDC", "1000", testSigner.address],
      ["WETH", "1000", testSigner.address],
    ]);
    const daiInc = lc.parseToken("1000", 18);
    const usdcInc = lc.parseToken("1000", 6);
    const wethInc = daiInc;

    lc.assertEqualBN(
      daiInc.add(daiAmount),
      await dai.balanceOf(testSigner.address),
      "Incorrect DAI balance"
    );
    lc.assertEqualBN(
      usdcInc.add(usdcAmount),
      await usdc.balanceOf(testSigner.address),
      "Incorrect USDC balance"
    );
    lc.assertEqualBN(
      wethInc.add(wethAmount),
      await wEth.balanceOf(testSigner.address),
      "Incorrect WETH balance"
    );
  });

  it("Testing AAVE", async function () {
    let aTokens = [
      await lc.getContract("AUSDC"),
      await lc.getContract("AWETH"),
      await lc.getContract("ADAI"),
    ];
    for (let aToken of aTokens) {
      let supply = await aToken.totalSupply();
      let sym = await aToken.symbol();
      console.log(
        `${sym} supply on mumbai: `,
        lc.formatToken(supply, await aToken.decimals())
      );
    }
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
