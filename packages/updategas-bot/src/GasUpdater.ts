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

  constructor(
    mangrove: Mangrove,
    provider: Provider,
    acceptableGasGapToOracle: number
  ) {
    this.#mangrove = mangrove;
    this.#provider = provider;
    this.#acceptableGasGapToOracle = acceptableGasGapToOracle;
  }

  public start() {
    // TODO: Each block is definitely too often - what is a good setting here, everytime change is deteced from external source?
    this.#provider.on("block", async (blocknumber) =>
      this.#checkSetGasprice(blocknumber)
    );
  }

  // TODO: Or just make checkSetGasPrice public
  public async checkSetGasPriceNow() {
    await this.#checkSetGasprice(-1);
  }

  async #checkSetGasprice(blocknumber: number) {
    //TODO: Probably suitable protection against reentrancy

    const globalConfig = await this.#mangrove.config();
    // FIXME: (common func) move to a property/method on Mangrove
    if (globalConfig.dead) {
      logger.debug(
        `Mangrove is dead at block number ${blocknumber}. Stopping MarketCleaner`
      );
      this.#provider.off("block", this.#checkSetGasprice);
      return;
    }

    logger.info(
      `Checking whether Mangrove gas price needs updating at block number ${blocknumber}`
    );

    const currentMangroveGasPrice = globalConfig.gasprice;

    logger.debug(
      `Current Mangrove gas price in config is: ${currentMangroveGasPrice}`
    );

    const oracleGasPriceEstimate = await this.#getGasPriceEstimateFromOracle();

    const [shouldUpdateGasPrice, newGasPrice] =
      await this.#shouldUpdateMangroveGasPrice(
        currentMangroveGasPrice,
        oracleGasPriceEstimate
      );

    if (shouldUpdateGasPrice) {
      await this.#updateMangroveGasPrice(newGasPrice);
    }
  }

  async #getGasPriceEstimateFromOracle(): Promise<number> {
    //TODO: stub implementation
    const oracleGasPrice = 2;
    logger.debug(
      `getGasPriceEstimateFromOracle: Stub implementation - using constant: ${oracleGasPrice}`
    );
    return oracleGasPrice;
  }

  async #shouldUpdateMangroveGasPrice(
    currentGasPrice: number,
    oracleGasPrice: number
  ): Promise<[Boolean, number]> {
    //TODO: stub implementation - also, if entirely local calc, may be sync

    logger.debug("shouldUpdateMangroveGasPrice: Naive implementation.");
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

  async #updateMangroveGasPrice(newGasPrice: number) {
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
