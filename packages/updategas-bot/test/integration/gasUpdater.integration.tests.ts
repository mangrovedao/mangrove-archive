/**
 * Integration tests of GasUpdater.ts.
 */
import { afterEach, before, beforeEach, describe, it } from "mocha";
import * as chai from "chai";
const { expect } = chai;
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);
import { Mangrove } from "@giry/mangrove-js";
import { Provider } from "@ethersproject/abstract-provider";
import { GasUpdater } from "../../src/GasUpdater";
import * as hre from "hardhat";
import "hardhat-deploy-ethers/dist/src/type-extensions";

describe("GasUpdater integration tests", () => {
  let provider: Provider;
  let mgv: Mangrove;

  beforeEach(async function () {
    //FIXME: for now we use the provider constructed by Mangrove -->
    provider = this.test?.parent?.parent?.ctx.provider;
    mgv = await Mangrove.connect({ provider });

    //TODO: The following should be able to be done with a mgv : Mangrove that has the right signer

    const deployer = (await hre.ethers.getNamedSigners()).deployer;
    const mgvContract = await hre.ethers.getContract("Mangrove", deployer);
    const mgvOracleContract = await hre.ethers.getContract(
      "MgvOracle",
      deployer
    );

    // FIXME: This only awaits tx receipts. Should really wait for tx's to be mined.
    await mgvContract.setMonitor(mgvOracleContract.address);
    await mgvContract.setUseOracle(true);
    await mgvContract.setNotify(true);
  });

  afterEach(async () => {
    await mgv.disconnect();
  });

  it("should set the gas price in Mangrove, when GasUpdater is run", async function () {
    const origMgvConfig = await mgv.config();

    const origGasPrice = origMgvConfig.gasprice;

    const gasUpdater = new GasUpdater(mgv, provider, 0.0);

    //TODO: Set mock value of gas-price-oracle
    const newGasPrice = 2;

    //TODO:Setup s.t. origGasPrice is guarenteed different than newGasPrice - temp check
    if (origGasPrice === newGasPrice) {
      throw new Error(
        `Test setup error: Mangrove gas price should be different than oracle price before invoking GasUpdater.`
      );
    }

    // Test
    await gasUpdater.checkSetGasprice(-1);

    // Assert
    const globalConfig = await mgv.config();
    return Promise.all([expect(globalConfig.gasprice).to.equal(newGasPrice)]);
  });
});
