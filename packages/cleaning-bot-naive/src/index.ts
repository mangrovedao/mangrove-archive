import { config } from "./util/config";
import { logger } from "./util/logger";
import { MarketCleaner } from "./MarketCleaner";
import { TokenPair } from "./mangrove-js-type-aliases";
// TODO Figure out where mangrove.js get its addresses from and make it configurable
import Mangrove from "@giry/mangrove-js";
import { Provider } from "@ethersproject/providers";
import { Wallet } from "@ethersproject/wallet";

const main = async () => {
  const mgv = await Mangrove.connect(config.get("jsonRpcUrl"));
  // TODO Initialize:
  // - Connect to Ethereum endpoint (Infura, Alchemy, ...)
  //   - Perhaps the safest is to connect to multiple by using the Ethers Default Provider?
  //     - https://docs.ethers.io/v5/api/providers/#providers-getDefaultProvider
  //     - Or is there a performance overhead that is problematic here?
  const provider = mgv._provider; // TODO
  // - Load private key and set up wallet for transaction signing
  const wallet = new Wallet(process.env["PRIVATE_KEY"] ?? "", provider); // TODO
  // - Connect Mangrove.js via the same provider
  // - Load the environment:
  //   - Addresses of relevant tokens and Mangrove on the chosen network
  //   - Load the ABI's and construct ethers.Contracts for relevant contracts
  //     - The cleaner contract
  //     - Liquidit sources (Aave, Compound)?
  //     - (Mangrove.js does this for its own contracts - maybe we should add that to the environment?)

  /* Get global config */
  const mgvConfig = await mgv.config();
  logger.info("Mangrove config retrieved", mgvConfig);

  /* TODO Should we subscribe to all open markets & monitor which markets exist and open?
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
   *
   * Or maybe it's better to just configure the markets we're interested in?
   */

  let marketCleanerMap = new Map<TokenPair, MarketCleaner>();

  /* Connect to market */
  // TODO Move token names to configuration
  const market = await mgv.market({
    base: "WETH",
    quote: "DAI",
  });

  marketCleanerMap.set(
    { base: market.base.name, quote: market.quote.name },
    new MarketCleaner(market, provider, wallet)
  );
};

main().catch((e) => logger.error(e));
