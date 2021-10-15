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
import { BookSide } from "../../src/mangrove-js-type-aliases";
import ethers from "ethers";
import { Provider } from "@ethersproject/abstract-provider";

import { MarketCleaner } from "../../dist/nodejs/MarketCleaner";

const bookSides: BookSide[] = ["asks", "bids"];

const awaitTransactionAndReceipt = async (
  contractTransactionPromise: Promise<ethers.ContractTransaction>
) => {
  let tx = await contractTransactionPromise.then((tx) => tx.wait());
};

describe("MarketCleaner integration tests", () => {
  let provider: Provider;
  let mgv: Mangrove;
  let market: Market;
  let testMakerContract: typechain.TestMaker;
  let getTokens = (bookSide: BookSide) => {
    return {
      inboundToken: bookSide === "asks" ? market.base : market.quote,
      outboundToken: bookSide === "asks" ? market.quote : market.base,
    };
  };

  beforeEach(async function () {
    // FIXME the hre.network.provider is not a full ethers Provider, e.g. it doesn't have getBalance() and getGasPrice()
    // FIXME for now we therefore use the provider constructed by Mangrove
    // provider = this.test?.parent?.parent?.ctx.provider;
    mgv = await Mangrove.connect(this.test?.parent?.parent?.ctx.providerUrl);
    provider = mgv._provider;
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

  bookSides.forEach((bookSide) => {
    it(`should clean offer failing to trade 0 wants on the '${bookSide}' offer list`, async function () {
      // Arrange
      // - Set up accounts
      //   - Which do we need?
      //     - (MGV admin account for opening market)
      //       - Market is already opened in the integration test hooks using (await ethers.getSigners())[0] - which I think is the 'deployer' account?
      //     - (Maker account for creating offer)
      //       - Could perhaps be the same as MGV admin? YES, doesn't matter for the tests, we only care about the cleaner and its account(s)
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
      // - Add offer to order book - using Mangrove.js if possible
      //   - Must be failing
      //   - Must not be persistent
      //   - Cleaning it must be profitable
      // TODO which account is used for this transaction - deployer, right?
      const { inboundToken, outboundToken } = getTokens(bookSide);
      await awaitTransactionAndReceipt(testMakerContract.shouldFail(true));
      await awaitTransactionAndReceipt(
        testMakerContract[
          "newOffer(address,address,uint256,uint256,uint256,uint256)"
        ](inboundToken.address, outboundToken.address, 1, 1000000, 100, 1)
      );
      // - Create MarketCleaner for the market
      //   - Must use the right account
      // FIXME must ensure that the right Signer is attached to the provider as TXs to the MgvCleaner contract must be signed
      const marketCleaner = new MarketCleaner(market, provider);

      const cleanerBalanceBefore = await provider.getBalance(
        mgv.cleanerContract.address
      );

      // Act
      await marketCleaner.clean(0);

      // Assert
      return Promise.all([
        // - Offer is not in the 'bookSide' offer list
        expect(market.requestBook()).to.eventually.have.property(bookSide).which
          .is.empty,
        // - Cleaner acct has more ether than before
        //   - Can we calculate exactly what the balance should be?
        expect(
          provider.getBalance(mgv.cleanerContract.address)
        ).to.eventually.satisfy((balanceAfter: ethers.BigNumber) =>
          balanceAfter.gt(cleanerBalanceBefore)
        ),
      ]);
    });
  });
});
