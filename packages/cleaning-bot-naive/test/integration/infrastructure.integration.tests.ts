/**
 * Test that integration test infrastructure is working.
 */
import { describe, it } from "mocha";
import chai from "chai";
const { expect } = chai;
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);
import Mangrove from "@giry/mangrove-js";
import { Provider } from "@ethersproject/abstract-provider";

declare module "mocha" {
  export interface Context {
    provider: Provider;
  }
}

describe("Can connect to Mangrove on local chain", () => {
  it("should be able to connect to Mangrove", function () {
    return expect(
      Mangrove.connect({ provider: this.test?.parent?.parent?.ctx.provider })
    ).to.eventually.be.fulfilled;
  });
});
