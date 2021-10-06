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

  before(async function () {
    // 1. mint (1000 dai, 1000 eth, 1000 weth) for testSigner
    // 2. activates (dai,weth) market
    dai = await lc.getContract("DAI");
    wEth = await lc.getContract("WETH");
    usdc = await lc.getContract("USDC");
    cwEth = await lc.getContract("CWETH");

    [testSigner] = await ethers.getSigners();

    await lc.fund([
      ["ETH", "10000.0", testSigner.address],
      ["WETH", "1000.0", testSigner.address],
      ["USDC", "1000.0", testSigner.address],
      //      ["DAI", "10000.0", testSigner.address]
    ]);
    let balusdc = await usdc.balanceOf(testSigner.address);
    console.log(
      lc.formatToken(balusdc, await usdc.decimals()),
      await usdc.symbol()
    );

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

    const filter_MissingPrice = makerContract.filters.MissingPrice();
    makerContract.once(filter_MissingPrice, (token0, token1, event) => {
      console.log("No price was defined for ", token0, token1);
      console.log();
    });
    const usdc_in_eth = lc.parseToken("0.0004", 18); // 1/2500
    const eth_in_usdc = lc.parseToken("2510", 18); // 2510

    await makerContract
      .connect(testSigner)
      .setPrice(wEth.address, usdc.address, eth_in_usdc);
    await makerContract
      .connect(testSigner)
      .setPrice(usdc.address, wEth.address, usdc_in_eth);

    await lc.fund([["ETH", "1.0", makerContract.address]]);

    let overrides = { value: lc.parseToken("2.0", 18) };
    const tx = await mgv["fund(address)"](makerContract.address, overrides);
    await tx.wait();

    const usdc_decimals = await usdc.decimals();
    const amount = lc.parseToken("1000.0", usdc_decimals);

    await makerContract
      .connect(testSigner)
      .startStrat(usdc.address, wEth.address, amount);

    // putting ethers on compound
    await wEth
      .connect(testSigner)
      .transfer(
        makerContract.address,
        lc.parseToken("1000.0", await lc.getDecimals("WETH"))
      );
    await makerContract
      .connect(testSigner)
      .approveLender(cwEth.address, ethers.constants.MaxUint256);

    const wethAmount = lc.parseToken("1000.0", 18);
    await makerContract.connect(testSigner).mint(cwEth.address, wethAmount);
    await makerContract.connect(testSigner).enterMarkets([cwEth.address]);
    await lc.logLenderStatus(makerContract, "compound", ["WETH"]);
    let book01 = await mgv.reader.book(usdc.address, wEth.address, 0, 1);
    let book10 = await mgv.reader.book(wEth.address, usdc.address, 0, 1);
    await lc.logOrderBook(book01, usdc, wEth);
    await lc.logOrderBook(book10, wEth, usdc);
  });
});
