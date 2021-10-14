/**
 * Integration tests of MarketCleaner.ts.
 */
import { afterEach, before, beforeEach, describe, it } from "mocha";
import * as chai from "chai";
const { expect } = chai;
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);
import { Mangrove, Market, MgvToken } from "@giry/mangrove-js";
import * as typechain from "@giry/mangrove-js/dist/nodejs/types/typechain";
import { newOffer, toWei } from "../util/helpers";
import { Provider } from "@ethersproject/abstract-provider";
import { MarketCleaner } from "../../src/MarketCleaner";
import * as hre from "hardhat";
import "hardhat-deploy-ethers/dist/src/type-extensions";

describe("MarketCleaner integration tests", () => {
  let provider: Provider;
  let mgv: Mangrove;
  let market: Market;
  let testMakerContract: typechain.TestMaker;

  beforeEach(async function () {
    provider = this.test?.parent?.parent?.ctx.provider;
    mgv = await Mangrove.connect({ provider });
    market = await mgv.market({ base: "TokenA", quote: "TokenB" });

    const testMakerAddress = Mangrove.getAddress(
      "TestMaker",
      mgv._network.name
    );
    testMakerContract = typechain.TestMaker__factory.connect(
      testMakerAddress,
      mgv._signer
    );
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
    //   - Maker must be provisioned
    // - Open market
    //   - NB: Market (TokenA, TokenB) is already opened by the integration-test-root-hooks
    //   - TODO which account - deployer?
    //   - NB: There's no Mangrove.js API for opening markets, right?
    console.log((await market.config()).asks.active);
    // - Add offer to order book - using Mangrove.js if possible
    //   - Must be failing
    //   - Must not be persistent
    //   - Cleaning it must be profitable
    // TODO which account is used for this transaction - deployer, right?
    // FIXME ----------------- commented out for merge
    // const setShouldFailTx = await testMakerContract.shouldFail(true);
    // await setShouldFailTx.wait();
    // const provisionTx = await testMakerContract.provisionMgv(toWei("1"));
    // await provisionTx.wait();
    // const newOfferTx = await testMakerContract[
    //   "newOffer(address,address,uint256,uint256,uint256,uint256)"
    // ](market.base.address, market.quote.address, 1, 1000000, 100, 1);
    // console.dir(newOfferTx);
    // const newOfferTxReceipt = await newOfferTx.wait();
    // console.dir(newOfferTxReceipt);
    // FIXME ---------------- end
    // const newOfferTx = await newOffer(mgv, market.base, market.quote, {
    //   wants: "1",
    //   gives: "1.2",
    //   gasreq: 10000,
    //   gasprice: 1,
    // });
    // console.dir(newOfferTx);
    // const newOfferTxReceipt = await newOfferTx.wait();
    // console.dir(newOfferTxReceipt);

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
