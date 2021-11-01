import { config } from "./util/config";
import { logger } from "./util/logger";

import Mangrove from "@giry/mangrove-js";
import { GasUpdater } from "./GasUpdater";

const main = async () => {
  // TODO: Indlæs env.local config og opsæt EOA og eth URL...
  const mgv = await Mangrove.connect(config.get<string>("jsonRpcUrl"));

  //NOTE: We probably want to fail more gracefully with a reasonable error-message,
  //      if we cannot connect. Right now, we fall into the main.exception handler.

  // TODO:
  const provider = mgv._provider;

  const acceptableGasGapToOracle = config.get<number>(
    "acceptableGasGapToOracle"
  );

  //TODO: gas price factor in config

  /* Get global config */
  const mgvConfig = await mgv.config();
  logger.info("Mangrove config retrieved", { data: mgvConfig });

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

//TODO: Promise unhandled handler

main().catch((e) => {
  //TODO: naive implementation
  logger.exception(e);
  process.exit(1);
});
