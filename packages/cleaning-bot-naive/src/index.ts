import { config } from "./util/config";
import { logger } from "./util/logger";
import Mangrove from "@giry/mangrove-js";
import { Market, Offer } from "@giry/mangrove-js/dist/nodejs/market";

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
  const subscriptionPromise = market.subscribe((marketUpdate) => {
    logger.info(
      `Received an update for market (${market.base.name}, ${market.quote.name})`,
      marketUpdate
    );
    // If its a write, we naively try to snipe the offer
    if (marketUpdate.type === "OfferWrite") {
      snipeOffer(market, marketUpdate.ba, marketUpdate.offer);
    }
  });

  await subscriptionPromise;

  logger.info(
    `Listening to order book updates for market (${market.base.name}, ${market.quote.name})...`
  );
};

function snipeOffer(market: Market, ba: String, offer: Offer) {
  logger.info(
    `Sniping offer ${offer.id} from ${ba} on market (${market.base.name}, ${market.quote.name})`
  );
}

main().catch((e) => console.error(e));
