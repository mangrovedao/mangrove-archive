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
  let gasUpdaterSigner: SignerWithAddress;
  let gasUpdaterProvider: Provider;

  let mgv: Mangrove;

  before(async function () {
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

  afterEach(() => {
    mgv.disconnect();
  });

  it("should set the gas price in Mangrove, when GasUpdater is run", async function () {
    // read in configured test config - skipping gas oracle URL, as we use constant here
    const acceptableGasGapToOracle = config.get<number>(
      "acceptableGasGapToOracle"
    );

    const constantGasPrice = config.get<number>("constantOracleGasPrice");

    // setup gasUpdater
    const gasUpdater = new GasUpdater(
      mgv,
      gasUpdaterProvider,
      acceptableGasGapToOracle,
      constantGasPrice,
      ""
    );

    // Test
    await gasUpdater.checkSetGasprice(-1);

    // Assert
    const globalConfig = await mgv.config();
    return Promise.all([
      expect(globalConfig.gasprice).to.equal(constantGasPrice),
    ]);
  });
});
