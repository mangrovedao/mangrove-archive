import mocha from "mocha";
const { describe, it } = mocha;
import chai from "chai";
const { expect } = chai;
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import Mangrove from "@mangrove-exchange/mangrove-js";

describe("Loading Mangrove.js", () => {
  it("should not be able to connect to Mangrove when no network is running", () => {
    return expect(Mangrove.connect("http://127.0.0.1:8545")).to.eventually.be
      .rejected;
  });
});
