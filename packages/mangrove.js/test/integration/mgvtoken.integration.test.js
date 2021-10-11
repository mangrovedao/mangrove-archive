const ethers = require("ethers");
const BigNumber = ethers.BigNumber;

const assert = require("assert");
const { Mangrove } = require("../../src");
const helpers = require("../util/helpers");

const { Big } = require("big.js");
//pretty-print when using console.log
Big.prototype[Symbol.for("nodejs.util.inspect.custom")] = function () {
  return `<Big>${this.toString()}`; // previously just Big.prototype.toString;
};

const newOffer = (mgv, base, quote, { wants, gives, gasreq, gasprice }) => {
  return mgv.contract.newOffer(
    base,
    quote,
    helpers.toWei(wants),
    helpers.toWei(gives),
    gasreq || 10000,
    gasprice || 1,
    0
  );
};

describe("MGV Token integration tests suite", () => {
  let mgv;

  beforeEach(async function () {
    //set mgv object
    mgv = await Mangrove.connect({
      provider: this.test?.parent?.parent?.ctx.provider,
    });

    //shorten polling for faster tests
    mgv._provider.pollingInterval = 250;
  });

  afterEach(async () => {
    mgv.disconnect();
  });

  it("reads allowance", async function () {
    const usdc = mgv.token("USDC");
    const allowance = await usdc.allowance();
    console.log(allowance);
    const resp = await usdc.approve(100);
    await resp.wait(1);
    const all = await usdc.allowance();
    console.log(all);
  });
});
