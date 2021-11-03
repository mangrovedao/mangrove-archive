import { config } from "./util/config";
import { logger } from "./util/logger";
import { GasUpdater, OracleSourceConfiguration } from "./GasUpdater";

import Mangrove from "@giry/mangrove-js";
import { JsonRpcProvider } from "@ethersproject/providers";
import { NonceManager } from "@ethersproject/experimental";
import { Wallet } from "@ethersproject/wallet";

import { ToadScheduler, SimpleIntervalJob, AsyncTask } from "toad-scheduler";

const scheduler = new ToadScheduler();

const main = async () => {
  logger.info("Starting gas-updater bot...");

  // read and use env config
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

  // read and use file config
  // - set defaults explicitly
  let acceptableGasGapToOracle = 0;
  let constantOracleGasPrice: number | undefined;
  let oracleURL = "";
  let oracleURL_Key = "";
  let runEveryXHours = 12; // twice a day, by default

  // - read in values
  if (config.has("acceptableGasGapToOracle")) {
    acceptableGasGapToOracle = config.get<number>("acceptableGasGapToOracle");
  }

  if (config.has("constantOracleGasPrice")) {
    constantOracleGasPrice = config.get<number>("constantOracleGasPrice");
  }

  if (config.has("oracleURL")) {
    oracleURL = config.get<string>("oracleURL");
  }

  if (config.has("runEveryXHours")) {
    runEveryXHours = config.get<number>("runEveryXHours");
  }

  if (config.has("oracleURL_Key")) {
    oracleURL_Key = config.get<string>("oracleURL_Key");
  }

  let oracleSourceConfiguration: OracleSourceConfiguration;
  // - config validation and logging
  //   if constant price set, use that and ignore other gas price config
  if (constantOracleGasPrice != null) {
    logger.info(
      `Configuration for constant oracle gas price found. Using the configured value.`,
      { data: constantOracleGasPrice }
    );

    oracleSourceConfiguration = {
      OracleGasPrice: constantOracleGasPrice,
      _tag: "Constant",
    };
  } else {
    // validate config
    if (
      oracleURL == null ||
      oracleURL == "" ||
      oracleURL_Key == null ||
      oracleURL_Key == ""
    ) {
      throw new Error(
        `Either 'constantOracleGasPrice' or the pair ('oracleURL', 'oracleURL_Key') must be set in config. Found values: constantOracleGasPrice: '${constantOracleGasPrice}', oracleURL: '${oracleURL}', oracleURL_Key: '${oracleURL_Key}'`
      );
    }
    logger.info(
      `Configuration for oracle endpoint found. Using the configured values.`,
      {
        data: { oracleURL, oracleURL_Key },
      }
    );

    oracleSourceConfiguration = {
      oracleEndpointURL: oracleURL,
      oracleEndpointKey: oracleURL_Key,
      _tag: "Endpoint",
    };
  }

  const gasUpdater = new GasUpdater(
    mgv,
    acceptableGasGapToOracle,
    oracleSourceConfiguration
  );

  // create and schedule task
  logger.info(`Running bot every ${runEveryXHours} hours.`);

  const task = new AsyncTask(
    "gas-updater bot task",
    async () => {
      const blockNumber = await mgv._provider.getBlockNumber().catch((e) => {
        logger.debug("Error on getting blockNumber via ethers", { data: e });
        return -1;
      });

      logger.verbose(`Scheduled bot task running on block ${blockNumber}...`);
      await exitIfMangroveIsKilled(mgv, blockNumber);
      await gasUpdater.checkSetGasprice();
    },
    (err: Error) => {
      logErrorAndExit(err);
    }
  );

  const job = new SimpleIntervalJob(
    {
      hours: runEveryXHours,
      runImmediately: true,
    },
    task
  );

  scheduler.addSimpleIntervalJob(job);
};

// NOTE: Almost equal to method in cleanerbot - commonlib.js candidate
async function exitIfMangroveIsKilled(
  mgv: Mangrove,
  blockNumber: number
): Promise<void> {
  const globalConfig = await mgv.config();
  if (globalConfig.dead) {
    logger.warn(
      `Mangrove is dead at block number ${blockNumber}. Stopping the bot.`
    );
    process.exit();
  }
}

function logErrorAndExit(err: Error) {
  logger.exception(err);
  scheduler.stop();
  process.exit(1);
}

process.on("unhandledRejection", function (reason, promise) {
  logger.warn("Unhandled Rejection", { data: reason });
});

main().catch((e) => {
  logErrorAndExit(e);
});
