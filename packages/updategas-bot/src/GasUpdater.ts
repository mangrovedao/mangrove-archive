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
  #constantOracleGasPrice: number | undefined;
  #oracleURL: string;

  /**
   * Constructs a GasUpdater bot.
   * @param mangrove A mangrove.js Mangrove object.
   * @param provider An ethers.js provider.
   * @param acceptableGasGapToOracle The allowed gap between the Mangrove gas
   * price and the external oracle gas price.
   * @param constantOracleGasPrice TODO:
   * @param oracleURL TODO:
   */
  constructor(
    mangrove: Mangrove,
    provider: Provider,
    acceptableGasGapToOracle: number,
    constantOracleGasPrice: number | undefined,
    oracleURL: string
  ) {
    this.#mangrove = mangrove;
    this.#provider = provider;
    this.#acceptableGasGapToOracle = acceptableGasGapToOracle;
    this.#constantOracleGasPrice = constantOracleGasPrice;
    this.#oracleURL = oracleURL;
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

    logger.debug("Mangrove global config retrieved", { data: globalConfig });

    const currentMangroveGasPrice = globalConfig.gasprice;

    const oracleGasPriceEstimate = await this.#getGasPriceEstimateFromOracle();

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
   * Either returns a constant gas price, if set, or queries a dedicated
   * external source for gas prices.
   * @returns {number} Promise object representing the gas price from the
   * external oracle
   */
  async #getGasPriceEstimateFromOracle(): Promise<number | undefined> {
    if (this.#constantOracleGasPrice !== undefined) {
      logger.debug(
        `'constantOracleGasPrice' set. Using the configured value.`,
        { data: this.#constantOracleGasPrice }
      );
      return this.#constantOracleGasPrice;
    }

    try {
      const { data } = await get(this.#oracleURL);
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
      // Round to closest integer before converting to BigNumber
      const newGasPriceRounded = Math.round(newGasPrice);

      await this.#mangrove.oracleContract
        .setGasPrice(newGasPriceRounded)
        .then((tx) => tx.wait());

      logger.info(
        `Succesfully sent Mangrove gas price update to oracle: ${newGasPriceRounded}.`
      );
    } catch (e) {
      logger.error("setGasprice failed", {
        mangrove: this.#mangrove,
        data: e,
      });
    }
  }
}
