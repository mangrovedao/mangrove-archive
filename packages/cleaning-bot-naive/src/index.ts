import { config } from "./util/config";
import { logger } from "./util/logger";
import { MarketCleaner } from "./MarketCleaner";
import { TokenPair } from "./TokenPair";
import Mangrove from "@giry/mangrove-js";

const main = async () => {
  const mgv = await Mangrove.connect(config.get("jsonRpcUrl"));

  /* Get global config */
  const mgvConfig = await mgv.config();
  logger.info("Mangrove config retrieved", mgvConfig);

  /* TODO Subscribe to all open markets & monitor which markets exist and open
   *
   * Pseudo code:
   *
   *   const markets = mgv.getMarkets();
   *   let marketCleanerMap = new Map<{base: String, quote: String}, MarketCleaner>();
   *   for (const market in markets) {
   *     marketCleanerMap.set({base: "A", quote: "B"}, MarketCleaner.create(market));
   *   }
   *
   *   mgv.subscribeToMarketUpdates((marketUpdate) => { add/remove market cleaner });
   *
   * NB: How do we ensure that we don't miss any market changes between initialization and subscription?
   *     Maybe subscribe first and then just buffer updates until initialization has completed?
   */

  let marketCleanerMap = new Map<TokenPair, MarketCleaner>();

  /* Connect to market */
  const market = await mgv.market({
    base: "TokenA",
    quote: "TokenB",
  });

  marketCleanerMap.set(
    { base: market.base.name, quote: market.quote.name },
    await MarketCleaner.create(market)
  );
};

main().catch((e) => console.error(e));
