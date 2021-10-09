import config from "./util/config";
import { ErrorWithData } from "@giry/commonlib-js";
import { MarketCleaner } from "./MarketCleaner";
import { logger } from "./util/logger";
import { TokenPair } from "./mangrove-js-type-aliases";
// TODO Figure out where mangrove.js get its addresses from and make it configurable
import Mangrove from "@giry/mangrove-js";
import { Provider } from "@ethersproject/providers";
import { Wallet } from "@ethersproject/wallet";

const main = async () => {
  const mgv = await Mangrove.connect(config.get<string>("jsonRpcUrl"));
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

  let marketCleanerMap = new Map<TokenPair, MarketCleaner>();

  provider.on("block", async (blockNumber) =>
    exitIfMangroveIsKilled(mgv, blockNumber)
  );

  /* Connect to markets */
  const marketConfigs = getMarketConfigsOrThrow();
  for (const marketConfig of marketConfigs) {
    if (!Array.isArray(marketConfig) || marketConfig.length != 2) {
      logger.error("Market configuration is malformed: Should be a pair", {
        data: marketConfig,
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

function getMarketConfigsOrThrow() {
  if (!config.has("markets")) {
    throw new Error("No markets have been configured");
  }
  const marketsConfig = config.get<Array<Array<string>>>("markets");
  if (!Array.isArray(marketsConfig)) {
    throw new ErrorWithData(
      "Markets configuration is malformed, should be an array of pairs",
      marketsConfig
    );
  }
  return marketsConfig;
}

main().catch((e) => {
  logger.exception(e);
  // TODO Consider doing graceful shutdown of market cleaners
  process.exit(1); // TODO Add exit codes
});
