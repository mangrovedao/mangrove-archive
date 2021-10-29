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
import { config } from "../../src/util/config";

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
    // Setup s.t. Mangrove is assured to need a gas price update
    const origMgvConfig = await mgv.config();
    const acceptableGasGapToOracle = config.get<number>(
      "acceptableGasGapToOracle"
    );
    const gasPriceFromOracle =
      origMgvConfig.gasprice + acceptableGasGapToOracle * 10 + 1;

    // Mock the function to get the price from the oracle
    const externalOracleMockGetter: () => Promise<number> = async () =>
      gasPriceFromOracle;

    // construct the gasUpdater with the mock for getting prices from the oracle
    const gasUpdater = new GasUpdater(
      mgv,
      provider,
      0.0,
      externalOracleMockGetter
    );

    // Test
    await gasUpdater.checkSetGasprice(-1);

    // Assert
    const globalConfig = await mgv.config();
    return Promise.all([
      expect(globalConfig.gasprice).to.equal(gasPriceFromOracle),
    ]);
  });
});