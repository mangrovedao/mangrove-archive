import { logger } from "./util/logger";
import { Market, Offer } from "@giry/mangrove-js/dist/nodejs/market";

export class MarketCleaner {
  #market: Market;

  private constructor(market: Market) {
    this.#market = market;
  }

  static async create(market: Market): Promise<MarketCleaner> {
    const marketCleaner = new MarketCleaner(market);

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
        marketCleaner.snipeOffer(marketUpdate.ba, marketUpdate.offer);
      }
    });

    await subscriptionPromise;

    logger.info(
      `Listening to order book updates for market (${market.base.name}, ${market.quote.name})...`
    );

    return marketCleaner;
  }

  snipeOffer(ba: String, offer: Offer) {
    logger.info(
      `Sniping offer ${offer.id} from ${ba} on market (${
        this.#market.base.name
      }, ${this.#market.quote.name})`
    );
  }
}
