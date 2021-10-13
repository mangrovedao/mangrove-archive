/**
 * Integration tests of MarketCleaner.ts.
 */
import { afterEach, beforeEach, describe, it } from "mocha";
import * as chai from "chai";
const { expect } = chai;
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);
import { Mangrove, Market, MgvToken } from "@giry/mangrove-js";
import { newOffer, sleep } from "../util/helpers";
import { Provider } from "@ethersproject/abstract-provider";
import { MarketCleaner } from "../../src/MarketCleaner";

describe("MarketCleaner integration tests", () => {
  let provider: Provider;
  let mgv: Mangrove;
  let market: Market;

  beforeEach(async function () {
    provider = this.test?.parent?.parent?.ctx.provider;
    mgv = await Mangrove.connect({ provider });
    market = await mgv.market({ base: "WETH", quote: "DAI" });
  });

  afterEach(async function () {
    market.disconnect();
    mgv.disconnect();
  });

  it("should clean offer failing to trade 0 wants on the 'asks' offer list", async function () {
    // Arrange
    // - Set up accounts
    //   - Which do we need?
    //     - MGV admin account for opening market
    //     - Maker account for creating offer
    //       - Could perhaps be the same as MGV admin?
    //     - Cleaner account for sending transactions
    //   - What funding do the accounts need?
    //     - Plenty of ether for gas - we're not testing out of gas here
    //     - Only Maker acct needs tokens
    //   - Do we need to set up any token approvals?
    //     - For ERC-20 tokens, I think both Maker acct and Cleaner acct need to be approved?
    //     - NB: MgvToken has utility function for approving
    // - Open market
    //   - TODO which account - deployer?
    //   - NB: There's no Mangrove.js API for opening markets, right?
    const feeInBasisPoints = 5;
    const density = 0;
    const overhead_gasbase = 1;
    const offer_gasbase = 2;
    await mgv.contract.activate(
      market.base.address,
      market.quote.address,
      feeInBasisPoints,
      density,
      overhead_gasbase,
      offer_gasbase
    );
    // FIXME We must activate the other side of the market even though we don't use it - that's counter-intuitive
    await mgv.contract.activate(
      market.quote.address,
      market.base.address,
      feeInBasisPoints,
      density,
      overhead_gasbase,
      offer_gasbase
    );
    console.log((await market.config()).asks.active);
    // - Add offer to order book - using Mangrove.js if possible
    //   - Must be failing
    //   - Must not be persistent
    //   - Cleaning it must be profitable
    // TODO which account is use for this transaction - deployer, right?
    const newOfferTx = await newOffer(mgv, market.base, market.quote, {
      wants: "1",
      gives: "1.2",
      gasreq: 10000,
      gasprice: 1,
    });
    console.dir(newOfferTx);
    const newOfferTxReceipt = await newOfferTx.wait();
    console.dir(newOfferTxReceipt);

    // Act
    // - Create MarketCleaner for the market
    //   - Must use the right account
    // - Wait for it to complete cleaning - HOW?
    const marketCleaner = new MarketCleaner(market, provider);
    await marketCleaner.cleanNow();

    // Assert
    return Promise.all([
      // - Offer is not in the 'asks' offer list
      expect(market.requestBook()).to.eventually.have.property("asks").which.is
        .empty,
      // - Cleaner acct has more ether than before
      //   - Can we calculate exactly what the balance should be?
    ]);
  });
});
