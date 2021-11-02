import { logger } from "./util/logger";
import Mangrove from "@giry/mangrove-js";
import { Provider } from "@ethersproject/providers";
import Big from "big.js";
import get from "axios";
Big.DP = 20; // precision when dividing
Big.RM = Big.roundHalfUp; // round to nearest

/**
 * A GasUpdater bot, which queries an external oracle for gas prices, and sends
 * gas price updates to Mangrove, through a dedicated oracle contract.
 */
export class GasUpdater {
  #mangrove: Mangrove;
  #provider: Provider;
  #acceptableGasGapToOracle: number;
  #externalGasOracleGetter: () => Promise<number | undefined>;
  #externalGasOracleURL = new URL("https://gasstation-mainnet.matic.network/");

  /**
   * Constructs a GasUpdater bot.
   * @param mangrove A mangrove.js Mangrove object.
   * @param provider An ethers.js provider.
   * @param acceptableGasGapToOracle The allowed gap between the Mangrove gas
   * price and the external oracle gas price.
   * @param externalGasOracleGetter An optional override for the function, which
   * contacts the external oracle. (Intended for testing.)
   */
  constructor(
    mangrove: Mangrove,
    provider: Provider,
    acceptableGasGapToOracle: number,
    externalGasOracleGetter?: () => Promise<number | undefined>
  ) {
    this.#mangrove = mangrove;
    this.#provider = provider;
    this.#acceptableGasGapToOracle = acceptableGasGapToOracle;
    if (externalGasOracleGetter !== undefined) {
      this.#externalGasOracleGetter = externalGasOracleGetter;
    } else {
      this.#externalGasOracleGetter = this.#getGasPriceEstimateFromOracle;
    }
  }

  /**
   * Start bot running.
   */
  public start(): void {
    // TODO: A few times a day, set in config
    this.#provider.on(
      "block",
      async (blocknumber) => await this.checkSetGasprice(blocknumber)
    );
  }

  /**
   * Checks an external oracle for an updated gas price, compares with the
   * current Mangrove gas price and, if deemed necessary, sends an updated
   * gas price to use to the oracle contract, which this bot works together
   * with.
   * @param blocknumber The current blocknumber - mainly used for logging.
   */
  public async checkSetGasprice(blocknumber: number): Promise<void> {
    //NOTE: Possibly suitable protection against reentrancy

    logger.info(
      `Checking whether Mangrove gas price needs updating at block number ${blocknumber}`
    );

    const globalConfig = await this.#mangrove.config();
    // FIXME: (common func) move to a property/method on Mangrove
    if (globalConfig.dead) {
      logger.debug(
        `Mangrove is dead at block number ${blocknumber}. Stopping Gas Updater`
      );
      this.#provider.off("block", this.checkSetGasprice);
      return;
    }

    logger.verbose("Mangrove global config retrieved", { data: globalConfig });

    const currentMangroveGasPrice = globalConfig.gasprice;

    logger.debug(
      `Current Mangrove gas price in config is: ${currentMangroveGasPrice}`
    );

    const oracleGasPriceEstimate = await this.#externalGasOracleGetter();

    if (oracleGasPriceEstimate !== undefined) {
      const [shouldUpdateGasPrice, newGasPrice] =
        this.#shouldUpdateMangroveGasPrice(
          currentMangroveGasPrice,
          oracleGasPriceEstimate
        );

      if (shouldUpdateGasPrice) {
        await this.#updateMangroveGasPrice(newGasPrice);
      }
    } else {
      logger.error("Could not contact oracle, skipping update.");
    }
  }

  /**
   * Standard implementation of a function, which queries a dedicated external
   * source for gas prices.
   * @returns {number} Promise object representing the gas price from the
   * external oracle
   */
  async #getGasPriceEstimateFromOracle(): Promise<number | undefined> {
    try {
      const { data } = await get(this.#externalGasOracleURL.toString());
      logger.debug(`Received this data from oracle.`, { data: data });
      return data.standard;
    } catch (error) {
      logger.error("Getting gas price estimate from oracle failed", {
        mangrove: this.#mangrove,
        data: error,
      });
    }
  }

  /**
   * Compare the current Mangrove gasprice with a gas price from the external
   * oracle, and decide whether a gas price update should be sent.
   * @param currentGasPrice Current gas price from Mangrove config.
   * @param oracleGasPrice Gas price from external oracle.
   * @returns {[boolean, number]} A pair representing (1) whether the Mangrove
   * gas price should be updated, and (2) what gas price to update to.
   */
  #shouldUpdateMangroveGasPrice(
    currentGasPrice: number,
    oracleGasPrice: number
  ): [boolean, number] {
    //NOTE: Very basic implementation allowing a configurable gap between
    //      Mangrove an oracle gas price.
    const shouldUpdate =
      Math.abs(currentGasPrice - oracleGasPrice) >
      this.#acceptableGasGapToOracle;

    if (shouldUpdate) {
      logger.debug(
        `shouldUpdateMangroveGasPrice: Determined update needed - to ${oracleGasPrice}`
      );
      return [true, oracleGasPrice];
    } else {
      logger.debug(
        `shouldUpdateMangroveGasPrice: Determined no update needed.`
      );
      return [false, oracleGasPrice];
    }
  }

  /**
   * Send a gas price update to the oracle contract, which Mangrove uses.
   * @param newGasPrice The new gas price.
   */
  async #updateMangroveGasPrice(newGasPrice: number): Promise<void> {
    logger.debug(
      "updateMangroveGasPrice: Sending gas update to oracle contract."
    );

    try {
      await this.#mangrove.oracleContract
        .setGasPrice(newGasPrice)
        .then((tx) => tx.wait());

      logger.info(
        `Succesfully sent Mangrove gas price update to oracle: ${newGasPrice}.`
      );
    } catch (e) {
      logger.error("setGasprice failed", {
        mangrove: this.#mangrove,
        data: e,
      });
    }
  }
}
