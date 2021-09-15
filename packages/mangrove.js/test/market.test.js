const ethers = require("ethers");
const BigNumber = ethers.BigNumber;

const assert = require("assert");
const { Mangrove } = require("../src/index.ts");
const providerUrl = "http://localhost:8545";

const { Big } = require("big.js");
//pretty-print when using console.log
Big.prototype[Symbol.for("nodejs.util.inspect.custom")] =
  Big.prototype.toString;

const toWei = (v, u = "ether") => ethers.utils.parseUnits(v.toString(), u);

const newOffer = (mgv, base, quote, { wants, gives, gasreq, gasprice }) => {
  return mgv.contract.newOffer(
    base,
    quote,
    toWei(wants),
    toWei(gives),
    gasreq,
    gasprice,
    0
  );
};

module.exports = function suite([publicKeys, privateKeys]) {
  const acc1 = { address: publicKeys[0], privateKey: privateKeys[0] };

  it("gets config", async function () {
    // Connect to mangrove
    const mgv = await Mangrove.connect(providerUrl, {
      privateKey: acc1.privateKey,
    });

    const fee = 13;
    const market = await mgv.market({ base: "TokenA", quote: "TokenB" });
    await mgv.contract.setFee(
      mgv.getAddress(market.base),
      mgv.getAddress(market.quote),
      fee
    );

    const config = await market.config();
    assert.strictEqual(config.asks.fee, fee, "wrong fee");
  });

  it("gets OB", async function () {
    // Connect to Mangrove
    const mgv = await Mangrove.connect(providerUrl, {
      privateKey: acc1.privateKey,
    });

    // Initialize A/B market.
    const market = await mgv.market({ base: "TokenA", quote: "TokenB" });

    /* create bids and asks */
    let asks = [
      { id: 1, wants: "1", gives: "1", gasreq: 10_000, gasprice: 1 },
      { id: 2, wants: "1.2", gives: "1", gasreq: 10_002, gasprice: 3 },
      { id: 3, wants: "1", gives: "1.2", gasreq: 9999, gasprice: 21 },
    ];

    let bids = [
      { id: 1, wants: "0.99", gives: "1", gasreq: 10_006, gasprice: 11 },
      { id: 2, wants: "1", gives: "1.43", gasreq: 9998, gasprice: 7 },
      { id: 3, wants: "1.11", gives: "1", gasreq: 10_022, gasprice: 30 },
    ];

    /* fill orderbook with bids and asks */
    /* note that we are NOT testing mangrove.js's newOffer function
     * so we create offers through ethers.js generic API */
    const addrA = mgv.getAddress("TokenA");
    const addrB = mgv.getAddress("TokenB");
    for (const ask of asks) await newOffer(mgv, addrA, addrB, ask);
    for (const bid of bids) await newOffer(mgv, addrB, addrA, bid);

    /* Now we create the orderbook we expect to get back so we can compare them */

    /* Reorder array a (array) such that an element with id i
     * goes to position o.indexOf(i). o is the order we want.
     */
    const reorder = (a, o) => o.map((i) => a[a.findIndex((e) => e.id == i)]);

    /* Put bids and asks in expected order (from best price to worse) */
    asks = reorder(asks, [3, 1, 2]);
    bids = reorder(bids, [2, 1, 3]);

    // Add price/volume, prev/next, +extra info to expected book.
    // Volume always in base, price always in quote/base.
    const config = await market.config();
    const complete = (isAsk, ary) => {
      return ary.map((ofr, i) => {
        const _config = config[isAsk ? "asks" : "bids"];
        const [baseVolume, quoteVolume] = isAsk
          ? ["gives", "wants"]
          : ["wants", "gives"];
        return {
          ...ofr,
          prev: ary[i - 1]?.id || 0,
          next: ary[i + 1]?.id || 0,
          volume: Big(ofr[baseVolume]),
          price: Big(ofr[quoteVolume]).div(Big(ofr[baseVolume])),
          maker: acc1.address,
          overhead_gasbase: _config.overhead_gasbase,
          offer_gasbase: _config.offer_gasbase,
        };
      });
    };

    // Reorder elements, add prev/next pointers
    asks = complete(true, asks);
    bids = complete(false, bids);

    /* Start testing */

    const book = await market.book({ maxOffers: 3 });

    // Convert big.js numbers to string for easier debugging
    const stringify = ({ bids, asks }) => {
      const s = (obj) => {
        return {
          ...obj,
          wants: obj.wants.toString(),
          gives: obj.gives.toString(),
          volume: obj.volume.toString(),
          price: obj.price.toString(),
        };
      };
      return { bids: bids.map(s), asks: asks.map(s) };
    };

    assert.deepStrictEqual(
      stringify(book),
      stringify({ bids, asks }),
      "bad book"
    );
  });

  it("does market buy", async function () {
    const mgv = await Mangrove.connect(providerUrl, {
      privateKey: acc1.privateKey,
    });

    // TODO
  });
};
