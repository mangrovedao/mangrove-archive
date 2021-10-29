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
import { SignerWithAddress } from "hardhat-deploy-ethers/dist/src/signers";

describe("GasUpdater integration tests", () => {
  let deployerSigner: SignerWithAddress;
  let gasUpdaterSigner: SignerWithAddress;
  let gasUpdaterProvider: Provider;

  let mgv: Mangrove;

  before(async function () {
    deployerSigner = await hre.ethers.getNamedSigner("deployer");
    gasUpdaterSigner = await hre.ethers.getNamedSigner("gasUpdater");
  });

  beforeEach(async function () {
    mgv = await Mangrove.connect({
      //FIXME: hacky -->
      provider: this.test?.parent?.parent?.ctx.provider,
      signer: gasUpdaterSigner,
    });
    gasUpdaterProvider = mgv._provider;

    //TODO: The following should be able to be done with a mgv : Mangrove that has the right signer

    const deployer = (await hre.ethers.getNamedSigners()).deployer;
    const mgvContract = await hre.ethers.getContract("Mangrove", deployer);
    const mgvOracleContract = await hre.ethers.getContract(
      "MgvOracle",
      deployer
    );

    await mgvContract.setMonitor(mgvOracleContract.address);
    await mgvContract.setUseOracle(true);
    await mgvContract.setNotify(true);

    const gasUpdater = gasUpdaterSigner.address;
    await mgvOracleContract.setMutator(gasUpdater);
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
      gasUpdaterProvider,
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
