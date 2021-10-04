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
  if (!process.env["PRIVATE_KEY_MNEMONIC"]) {
    logger.error("No mnemonic provided in PRIVATE_KEY_MNEMONIC");
    throw new Error("No mnemonic provided in PRIVATE_KEY_MNEMONIC");
  }
  const mnemonic = process.env["PRIVATE_KEY_MNEMONIC"];
  const wallet = Wallet.fromMnemonic(mnemonic); // TODO
  // - Connect Mangrove.js via the same provider
  // - Load the environment:
  //   - Addresses of relevant tokens and Mangrove on the chosen network
  //   - Load the ABI's and construct ethers.Contracts for relevant contracts
  //     - The cleaner contract
  //     - Liquidit sources (Aave, Compound)?
  //     - (Mangrove.js does this for its own contracts - maybe we should add that to the environment?)

  /* Get global config */
  const mgvConfig = await mgv.config();
  logger.info("Mangrove config retrieved", { data: mgvConfig });

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

  provider.on("block", async (blockNumber) =>
    exitIfMangroveIsKilled(mgv, blockNumber)
  );

  /* Connect to market */
  if (!config.has("markets")) {
    logger.error("No markets have been configured");
    return;
  }
  const marketsConfig = config.get("markets");
  if (!Array.isArray(marketsConfig)) {
    logger.error(
      "Markets configuration is malformed: Should be an array of pairs",
      { data: JSON.stringify(marketsConfig) }
    );
    return;
  }
  for (const marketConfig of marketsConfig) {
    if (!Array.isArray(marketConfig) || marketConfig.length != 2) {
      logger.error("Market configuration is malformed: Should be a pair", {
        data: JSON.stringify(marketConfig),
      });
      return;
    }
    const [token1, token2] = marketConfig;
    const market = await mgv.market({
      base: token1,
      quote: token2,
    });

    marketCleanerMap.set(
      { base: market.base.name, quote: market.quote.name },
      new MarketCleaner(market, provider, wallet)
    );
  }
};

async function exitIfMangroveIsKilled(
  mgv: Mangrove,
  blockNumber: number
): Promise<void> {
  const globalConfig = await mgv.config();
  // FIXME maybe this should be a property/method on Mangrove.
  if (globalConfig.dead) {
    logger.warn(
      `Mangrove is dead at block number ${blockNumber}. Stopping the bot`
    );
    process.exit();
  }
}

main().catch((e) => logger.error(e));
