import config from "./util/config";
import { logger } from "./util/logger";

import Mangrove from "@giry/mangrove-js";
import { GasUpdater } from "./GasUpdater";

const main = async () => {
  const mgv = await Mangrove.connect(config.get<string>("jsonRpcUrl"));
  //TODO: Fail gracefully with an error-message if cannot connect

  // TODO:
  const provider = mgv._provider;

  /* Get global config */
  const mgvConfig = await mgv.config();
  logger.info("Mangrove config retrieved", { data: mgvConfig });

  provider.on("block", async (blockNumber) =>
    exitIfMangroveIsKilled(mgv, blockNumber)
  );

  const gasUpdater = new GasUpdater(mgv, provider);
  gasUpdater.start();
};

// TODO: Exact same as in cleanerbot - maybe common functionality
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
