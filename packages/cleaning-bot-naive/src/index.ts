import { config } from "./util/config";
import { logger } from "./util/logger";
import Mangrove from "@giry/mangrove-js";

const main = async () => {
  const mgv = await Mangrove.connect(config.get("jsonRpcUrl"));

  /* Get global config */
  const mgvConfig = await mgv.config();
  logger.info("Mangrove config retrieved", mgvConfig);

  /* Connect to market */
  const baseTokenName = "TokenA";
  const quoteTokenName = "TokenB";

  const market = await mgv.market({
    base: baseTokenName,
    quote: quoteTokenName,
  });
  const marketConfig = await market.config();

  logger.info(
    `Market config for (${market.base.name}, ${market.quote.name}) retrieved`,
    marketConfig
  );

  /* Get order book */
  const orderBook = await market.book();
  logger.info(
    `Order book for (${market.base.name}, ${market.quote.name}) retrieved`,
    { asksCount: orderBook.asks.length, bidsCount: orderBook.bids.length }
  );

  /* Subscribe to market updates */
  const subscriptionPromise = market.subscribe((x) => {
    logger.info(
      `Received an update for market (${market.base.name}, ${market.quote.name})`,
      x
    );
  });

  await subscriptionPromise;
};

main().catch((e) => console.error(e));
