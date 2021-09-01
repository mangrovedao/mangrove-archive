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

module.exports = function suite([publicKeys, privateKeys]) {
  const acc1 = { address: publicKeys[0], privateKey: privateKeys[0] };

  it("gets config", async function () {
    const mgv = await Mangrove.connect(providerUrl, {
      privateKey: acc1.privateKey,
    });

    const fee = 13n;
    const market = await mgv.market({ base: "TokenA", quote: "TokenB" });
    await mgv.contract.setFee(
      mgv.getAddress(market.base),
      mgv.getAddress(market.quote),
      fee
    );

    const config = await market.config();
    assert.strictEqual(config.fee.toBigInt(), fee, "wrong gasprice");
  });

  it("gets OB", async function () {
    const mgv = await Mangrove.connect(providerUrl, {
      privateKey: acc1.privateKey,
    });

    const addrA = mgv.getAddress("TokenA");
    const addrB = mgv.getAddress("TokenB");
    const newOffer = async (
      base,
      quote,
      { wants, gives, gasreq, gasprice }
    ) => {
      await mgv.contract.newOffer(
        base,
        quote,
        toWei(wants),
        toWei(gives),
        gasreq,
        gasprice,
        0
      );
    };

    // Reorder array ary such that an element with id i is in position order.indexOf(i)
    const reorder = (ary, order) =>
      order.map((i) => ary[ary.findIndex((o) => o.id == i)]);

    let asks = [
      { id: 1, wants: Big("1"), gives: Big("1"), gasreq: 10_000, gasprice: 1 },
      {
        id: 2,
        wants: Big("1.2"),
        gives: Big("1"),
        gasreq: 10_002,
        gasprice: 3,
      },
      { id: 3, wants: Big("1"), gives: Big("1.2"), gasreq: 9999, gasprice: 21 },
    ];

    for (const ask of asks) await newOffer(addrA, addrB, ask);

    asks = reorder(asks, [3, 1, 2]);

    let bids = [
      {
        id: 1,
        wants: Big("0.99"),
        gives: Big("1"),
        gasreq: 10_006,
        gasprice: 11,
      },
      { id: 2, wants: Big("1"), gives: Big("1.43"), gasreq: 9998, gasprice: 7 },
      {
        id: 3,
        wants: Big("1.11"),
        gives: Big("1"),
        gasreq: 10_022,
        gasprice: 30,
      },
    ];

    for (const bid of bids) await newOffer(addrB, addrA, bid);

    bids = reorder(bids, [2, 1, 3]);

    const market = await mgv.market({ base: "TokenA", quote: "TokenB" });

    let book = await market.book({ maxOffers: 3 });

    // Add price/volume to expected book.
    // Volume always in base, price always in quote/base.
    const complete = (isAsk, ary) => {
      return ary.map((ofr, i) => {
        const [baseVolume, quoteVolume] = isAsk
          ? ["gives", "wants"]
          : ["wants", "gives"];
        return {
          ...ofr,
          prev: ary[i - 1]?.id || 0,
          next: ary[i + 1]?.id || 0,
          volume: ofr[baseVolume],
          price: ofr[quoteVolume].div(ofr[baseVolume]),
          maker: acc1.address,
          overhead_gasbase: 80000,
          offer_gasbase: 20000,
        };
      });
    };

    // Reorder elements, add prev/next pointers
    asks = complete(true, asks);
    bids = complete(false, bids);

    // Convert big.js numbers to string for easier debugging
    const stringify = (obj) => {
      return {
        ...obj,
        wants: obj.wants.toString(),
        gives: obj.gives.toString(),
        volume: obj.volume.toString(),
        price: obj.price.toString(),
      };
    };

    book = {
      asks: book.asks.map(stringify),
      bids: book.bids.map(stringify),
    };

    expectedBook = {
      asks: asks.map(stringify),
      bids: bids.map(stringify),
    };

    assert.deepStrictEqual(book, expectedBook, "bad book");
  });

  it("does market buy", async function () {
    // TODO
  });
};
