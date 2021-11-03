const hre = require("hardhat");
const helpers = require("../util/helpers");
const Mangrove = require("../../src/mangrove");
const hardhatUtils = require("@giry/hardhat-mangrove/hardhat-utils");
const { BigNumber } = require("@ethersproject/bignumber");
const seed =
  Math.random().toString(36).substring(2, 15) +
  Math.random().toString(36).substring(2, 15);
console.log(`random seed: ${seed}`);
const rng = require("seedrandom")(seed);

const _argv = require("minimist")(process.argv.slice(2), { boolean: "cross" });
const opts = {
  url: _argv.url || null,
  port: _argv.port || 8546,
  logging: _argv.logging || false,
  cross: _argv.cross,
};

const main = async () => {
  const _url = opts.url || `http://localhost:${opts.port}`;

  console.log(`${opts.url ? "Connecting" : "Starting"} RPC node on ${_url}`);

  if (!opts.url) {
    const mgvServer = require("./mgvServer");
    await mgvServer(opts);
  }

  const provider = new hre.ethers.providers.JsonRpcProvider(_url);

  const { Mangrove } = require("../../src");

  const deployer = (await hre.ethers.getSigners())[1];

  const user = (await hre.ethers.getSigners())[0];

  const mgv = await Mangrove.connect({
    signerIndex: 1,
    provider: `http://localhost:${opts.port}`,
  });

  // contract create2 addresses exported by mangrove-solidity to hardhatAddresses

  // const mgvContract = mgv.contract;
  const mgvReader = mgv.readerContract;
  console.log("mgvReader", mgvReader.address);

  const newOffer = async (
    tkout,
    tkin,
    wants,
    gives,
    gasreq = 100_000,
    gasprice = 1
  ) => {
    try {
      await mgv.contract.newOffer(
        tkout.address,
        tkin.address,
        tkin.toUnits(wants),
        tkout.toUnits(gives),
        gasreq,
        gasprice,
        0
      );
    } catch (e) {
      console.log(e);
      console.warn(
        `Posting offer failed - tkout=${tkout}, tkin=${tkin}, wants=${wants}, gives=${gives}, gasreq=${gasreq}, gasprice=${gasprice}`
      );
    }
  };

  const retractOffer = async (base, quote, offerId) => {
    const estimate = await mgv.contract.estimateGas.retractOffer(
      base,
      quote,
      offerId,
      true
    );
    const newEstimate = Math.round(estimate.toNumber() * 1.3);
    const resp = await mgv.contract.retractOffer(base, quote, offerId, true, {
      gasLimit: newEstimate,
    });
    const receipt = await resp.wait();
    if (!estimate.eq(receipt.gasUsed)) {
      console.log(
        "estimate != used:",
        estimate.toNumber(),
        receipt.gasUsed.toNumber()
      );
    }
    return mgv.contract.retractOffer(base, quote, offerId, true);
  };

  const between = (a, b) => a + rng() * (b - a);

  const WethDai = await mgv.market({ base: "WETH", quote: "DAI" });
  const WethUsdc = await mgv.market({ base: "WETH", quote: "USDC" });
  const DaiUsdc = await mgv.market({ base: "DAI", quote: "USDC" });

  const markets = [WethDai, WethUsdc, DaiUsdc];

  console.log("Orderbook filler is now running.");

  // Disable automine and set interval mining instead for more realistic behaviour + this allows queuing of TX's
  await provider.send("evm_setAutomine", [false]);
  await provider.send("evm_setIntervalMining", [1000]);

  const pushOffer = async (market, ba /*bids|asks*/) => {
    let tkout = "base",
      tkin = "quote";
    if (ba === "bids") [tkout, tkin] = [tkin, tkout];
    const book = await market.book();
    const buffer = book[ba].length > 30 ? 5000 : 0;

    setTimeout(async () => {
      let wants, gives;
      if (opts.cross) {
        if (tkin === "quote") {
          wants = 1 + between(0, 0.5);
          gives = 1;
          console.log("posting ask, price is ", wants / gives);
        } else {
          gives = 0.5 + between(0.3, 0.8);
          wants = 1;
          console.log("posting bid, price is ", gives / wants);
        }

        console.log();
      } else {
        wants = 1 + between(0, 3);
        gives = wants * between(1.001, 4);
      }
      console.log(
        `new ${market.base.name}/${market.quote.name} offer. price ${
          tkin === "quote" ? wants / gives : gives / wants
        }. wants:${wants}. gives:${gives}`
      );
      const cfg = await market.config();
      console.log(`asks last`, cfg.asks.last, `bids last`, cfg.bids.last);
      await newOffer(market[tkout], market[tkin], wants, gives);
      pushOffer(market, ba);
    }, between(1000 + buffer, 3000 + buffer));
  };

  const pullOffer = async (market, ba) => {
    let base = "base",
      quote = "quote";
    if (ba === "bids") [base, quote] = [quote, base];
    const book = await market.book();

    if (book[ba].length !== 0) {
      const pulledIndex = Math.floor(rng() * book[ba].length);
      const offer = book[ba][pulledIndex];
      console.log(
        `retracting on ${market.base.name}/${market.quote.name} ${offer.id}`
      );
      await retractOffer(market[base].address, market[quote].address, offer.id);
    }
    setTimeout(() => {
      pullOffer(market, ba);
    }, between(2000, 4000));
  };

  for (const market of markets) {
    pushOffer(market, "asks");
    pushOffer(market, "bids");
    pullOffer(market, "asks");
    pullOffer(market, "bids");
  }
};

main().catch((e) => console.error(e));
