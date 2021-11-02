import { config } from "./util/config";
import { logger } from "./util/logger";
import { GasUpdater } from "./GasUpdater";

import Mangrove from "@giry/mangrove-js";
import { JsonRpcProvider } from "@ethersproject/providers";
import { NonceManager } from "@ethersproject/experimental";
import { Wallet } from "@ethersproject/wallet";

const main = async () => {
  logger.info("Starting gas-updater bot...");

  if (!process.env["ETHEREUM_NODE_URL"]) {
    throw new Error("No URL for a node has been provided in ETHEREUM_NODE_URL");
  }
  if (!process.env["PRIVATE_KEY"]) {
    throw new Error("No private key provided in PRIVATE_KEY");
  }
  const provider = new JsonRpcProvider(process.env["ETHEREUM_NODE_URL"]);
  const signer = new Wallet(process.env["PRIVATE_KEY"], provider);
  const nonceManager = new NonceManager(signer);
  const mgv = await Mangrove.connect({
    provider: process.env["ETHEREUM_NODE_URL"],
    signer: nonceManager,
  });

  const acceptableGasGapToOracle = config.get<number>(
    "acceptableGasGapToOracle"
  );

  //TODO: read and instrument with gas price factor from file config

  //TODO: Run a few times a day (config'ed)
  provider.on("block", (blockNumber) =>
    exitIfMangroveIsKilled(mgv, blockNumber)
  );

  const gasUpdater = new GasUpdater(mgv, provider, acceptableGasGapToOracle);
  gasUpdater.start();
};

// FIXME: Exact same as in cleanerbot - commonlib.js candidate
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

process.on("unhandledRejection", function (reason, promise) {
  logger.warn("Unhandled Rejection", { data: reason });
});

main().catch((e) => {
  //NOTE: naive implementation
  logger.exception(e);
  process.exit(1);
});
