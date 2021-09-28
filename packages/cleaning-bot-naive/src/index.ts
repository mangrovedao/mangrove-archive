import dotenvFlow from "dotenv-flow";
dotenvFlow.config();
if (!process.env["NODE_CONFIG_DIR"]) {
  process.env["NODE_CONFIG_DIR"] = __dirname + "/config/";
}
import config from "config";

import Mangrove from "@giry/mangrove-js";

const main = async () => {
  const mgv = await Mangrove.connect(config.get("jsonRpcUrl"));

  /* Get global config */
  const mgvConfig = await mgv.config();
  console.log("Mangrove config:");
  console.dir(mgvConfig);

  /* Connect to market */
  const baseTokenName = "TokenA";
  const quoteTokenName = "TokenB";

  const market = await mgv.market({
    base: baseTokenName,
    quote: quoteTokenName,
  });
  const marketConfig = await market.config();

  console.log(`Market config for (${market.base.name}, ${market.quote.name}):`);
  console.dir(marketConfig);

  /* Get order book */
  const orderBook = await market.book();
  console.log(`Order book for (${market.base.name}, ${market.quote.name}):`);
  console.dir(orderBook);
};

main().catch((e) => console.error(e));
