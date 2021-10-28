import { logger } from "./util/logger";
import Mangrove, { ethers } from "@giry/mangrove-js";
import { Provider } from "@ethersproject/providers";
import Big from "big.js";
Big.DP = 20; // precision when dividing
Big.RM = Big.roundHalfUp; // round to nearest

export class GasUpdater {
  #mangrove: Mangrove;
  #provider: Provider;
  #acceptableGasGapToOracle: number;
  #externalOracleGetter: () => Promise<number>;

  constructor(
    mangrove: Mangrove,
    provider: Provider,
    acceptableGasGapToOracle: number,
    externalOracleGetter?: () => Promise<number>
  ) {
    this.#mangrove = mangrove;
    this.#provider = provider;
    this.#acceptableGasGapToOracle = acceptableGasGapToOracle;
    if (typeof externalOracleGetter !== "undefined") {
      this.#externalOracleGetter = externalOracleGetter;
    } else {
      this.#externalOracleGetter = this.getGasPriceEstimateFromOracle;
    }
  }

  /**
   * Start bot running.
   */
  public start(): void {
    // TODO: Each block is definitely too often - what is a good setting here, everytime change is deteced from external source?
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
    //TODO: Probably suitable protection against reentrancy

    const globalConfig = await this.#mangrove.config();
    // FIXME: (common func) move to a property/method on Mangrove
    if (globalConfig.dead) {
      logger.debug(
        `Mangrove is dead at block number ${blocknumber}. Stopping MarketCleaner`
      );
      this.#provider.off("block", this.checkSetGasprice);
      return;
    }

    logger.info(
      `Checking whether Mangrove gas price needs updating at block number ${blocknumber}`
    );

    const currentMangroveGasPrice = globalConfig.gasprice;

    logger.debug(
      `Current Mangrove gas price in config is: ${currentMangroveGasPrice}`
    );

    const oracleGasPriceEstimate = await this.#externalOracleGetter();

    const [shouldUpdateGasPrice, newGasPrice] =
      this.#shouldUpdateMangroveGasPrice(
        currentMangroveGasPrice,
        oracleGasPriceEstimate
      );

    if (shouldUpdateGasPrice) {
      await this.#updateMangroveGasPrice(newGasPrice);
    }
  }

  /**
   * Standard implementation of a function to query a dedicated external source
   * for gas prices.
   * @returns {number} Promise object representing the gas price from the
   * external oracle
   */
  public async getGasPriceEstimateFromOracle(): Promise<number> {
    //TODO: Missing
    const oracleGasPrice = 2;
    logger.debug(
      `getGasPriceEstimateFromOracle: Stub implementation - using constant: ${oracleGasPrice}`
    );
    return oracleGasPrice;
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
    logger.debug(
      "shouldUpdateMangroveGasPrice: Basic implementation allowing a configurable gap between Mangrove an oracle gas price."
    );
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
        .setGasPrice(ethers.BigNumber.from(newGasPrice))
        .then((tx) => tx.wait());
    } catch (e) {
      logger.error("setGasprice failed", {
        mangrove: this.#mangrove,
        data: e,
      });

      return;
    }

    logger.info(
      `Succesfully sent Mangrove gas price update to oracle: ${newGasPrice}.`
    );
  }
}
