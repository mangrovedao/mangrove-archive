const ethers = require("ethers");
const BigNumber = ethers.BigNumber;

const assert = require("assert");
const { Mangrove } = require("../src");
const providerUrl = "http://localhost:8546";
const helpers = require("./helpers");

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

module.exports = function suite() {
  let mgv;

  before(async () => {
    //set mgv object
    mgv = await Mangrove.connect(providerUrl);

    //shorten polling for faster tests
    mgv._provider.pollingInterval = 250;
  });

  it("test A", async function () {
    const market = await mgv.market({ base: "TokenA", quote: "TokenB" });
    const addrA = market.base.address;
    const addrB = market.quote.address;

    newOffer(mgv, addrA, addrB, { wants: "1", gives: "1.2" });

    /* If I remove await here, 
    then "test B" does not hang */
    await market.once(() => {});
  });

  it("test B", async function () {
    const market = await mgv.market({ base: "TokenA", quote: "TokenB" });
    const addrA = market.base.address;
    const addrB = market.quote.address;

    let pro1 = market.once((evt) => {
      assert.equal(
        market.book().asks.length,
        1,
        "book should have length 1 by now"
      );
    });
    await newOffer(mgv, addrA, addrB, { wants: "1", gives: "1.2" });
    await pro1;
  });
};
