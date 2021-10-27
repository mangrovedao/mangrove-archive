import { config } from "./util/config";
import { logger } from "./util/logger";

import Mangrove from "@giry/mangrove-js";
import { GasUpdater } from "./GasUpdater";

const main = async () => {
  const mgv = await Mangrove.connect(config.get<string>("jsonRpcUrl"));

  //NOTE: We probably want to fail more gracefully with a reasonable error-message,
  //      if we cannot connect. Right now, we fall into the main.exception handler.

  // TODO:
  const provider = mgv._provider;

  const acceptableGasGapToOracle = config.get<number>(
    "acceptableGasGapToOracle"
  );

  /* Get global config */
  const mgvConfig = await mgv.config();
  logger.info("Mangrove config retrieved", { data: mgvConfig });

  provider.on("block", async (blockNumber) =>
    exitIfMangroveIsKilled(mgv, blockNumber)
  );

  const gasUpdater = new GasUpdater(mgv, provider, acceptableGasGapToOracle);
  gasUpdater.start();
};

// FIXME: Exact same as in cleanerbot - maybe parts are commonlib.js candidates
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

main().catch((e) => {
  //TODO: naive implementation
  logger.exception(e);
  process.exit(1);
});
