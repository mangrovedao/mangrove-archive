import dotenvFlow from "dotenv-flow";
dotenvFlow.config();
if (!process.env["NODE_CONFIG_DIR"]) {
  process.env["NODE_CONFIG_DIR"] = __dirname + "/config/";
}
import config from "config";

import Mangrove from "../../../mangrove.js/src/index";

const main = async () => {
  const mgv = await Mangrove.connect("http://127.0.0.1:8545"); // TODO move connection string / network name to configuration

  //FIXME Currently doesn't work
  //const cfg = await mgv.config();

  const baseTokenName = "TokenA";
  const quoteTokenName = "TokenB";
  await mgv.cacheDecimals(baseTokenName);
  await mgv.cacheDecimals(quoteTokenName);

  const market = await mgv.market({base: baseTokenName, quote: quoteTokenName});
  const {asks, bids} = await market.config();
  console.dir(asks);

  if (!asks.active) {
    throw new Error(`Market is not active so exiting - market: base = ${baseTokenName}, quote = ${quoteTokenName}`);
  }
}

main();