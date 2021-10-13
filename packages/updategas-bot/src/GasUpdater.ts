import { logger } from "./util/logger";
import Mangrove from "@giry/mangrove-js";
import { Provider } from "@ethersproject/providers";
import Big from "big.js";

export class GasUpdater {
  #mangrove: Mangrove;
  #provider: Provider;

  constructor(mangrove: Mangrove, provider: Provider) {
    this.#mangrove = mangrove;
    this.#provider = provider;
  }

  public start() {
    // TODO: Each block is definitely too often - what is a good setting here?
    this.#provider.on("block", async (blocknumber) =>
      this._checkSetGasprice(blocknumber)
    );
  }

  private async _checkSetGasprice(blocknumber: any) {
    //TODO: Suitable protection against reentrancy

    const globalConfig = await this.#mangrove.config();
    // FIXME: (common func) move to a property/method on Mangrove
    if (globalConfig.dead) {
      logger.debug(
        `Mangrove is dead at block number ${blocknumber}. Stopping MarketCleaner`
      );
      this.#provider.off("block", this._checkSetGasprice);
      return;
    }

    logger.info(
      `Checking whether Mangrove gas price needs updating at block number ${blocknumber}`
    );

    const currentMangroveGasPrice = Big(globalConfig.gasprice);

    logger.debug(
      `Current Mangrove gas price in config is: ${currentMangroveGasPrice}`
    );

    const oracleGasPriceEstimate = await this._getGasPriceEstimateFromOracle();

    const [shouldUpdateGasPrice, newGasPrice] =
      await this._shouldUpdateMangroveGasPrice(
        currentMangroveGasPrice,
        oracleGasPriceEstimate
      );

    if (shouldUpdateGasPrice) {
      await this._updateMangroveGasPrice(newGasPrice);
    }
  }

  private async _getGasPriceEstimateFromOracle(): Promise<Big> {
    //TODO: stub implementation
    const oracleGasPrice = Big(2);
    logger.debug(
      `_getGasPriceEstimateFromOracle not implemented yet. Getting gas price from oracle in - using stub price: ${oracleGasPrice}`
    );
    return oracleGasPrice;
  }

  private async _shouldUpdateMangroveGasPrice(
    currentGasPrice: Big,
    oracleGasPrice: Big
  ): Promise<[Boolean, Big]> {
    //TODO: stub implementation - if entirely local calc, may be sync
    logger.debug("_shouldUpdateMangroveGasPrice not implemented yet.");

    if (currentGasPrice.eq(oracleGasPrice)) {
      return [true, oracleGasPrice];
    } else {
      return [false, oracleGasPrice];
    }
  }

  private async _updateMangroveGasPrice(oracleGasPriceEstimate: Big) {
    //TODO: Not implemented yet
    logger.debug("_updateMangroveGasPrice not implemented yet.");
    throw new Error("Function not implemented.");
  }
}
