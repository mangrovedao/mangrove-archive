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
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import { ethers as hardhatEthers } from "hardhat";
import { Provider } from "@ethersproject/abstract-provider";
import { SignerWithAddress } from "hardhat-deploy-ethers/dist/src/signers";
import { MarketCleaner } from "../../dist/nodejs/MarketCleaner";

const bookSides: BookSide[] = ["asks", "bids"];

describe("MarketCleaner integration tests", () => {
  let cleanerProvider: Provider;
  let mgv: Mangrove;
  let market: Market;
  let testMakerContract: typechain.TestMaker;
  let getTokens = (bookSide: BookSide) => {
    return {
      inboundToken: bookSide === "asks" ? market.base : market.quote,
      outboundToken: bookSide === "asks" ? market.quote : market.base,
    };
  };

  let deployerSigner: SignerWithAddress;
  let makerSigner: SignerWithAddress;
  let cleanerSigner: SignerWithAddress;

  before(async function () {
    deployerSigner = await hardhatEthers.getNamedSigner("deployer"); // Owner of deployed MGV and token contracts
    makerSigner = await hardhatEthers.getNamedSigner("maker"); // Owner of TestMaker contract
    cleanerSigner = await hardhatEthers.getNamedSigner("cleaner"); // Owner of cleaner EOA
  });

  beforeEach(async function () {
    // FIXME the hre.network.provider is not a full ethers Provider, e.g. it doesn't have getBalance() and getGasPrice()
    // FIXME for now we therefore use the provider constructed by Mangrove
    // provider = this.test?.parent?.parent?.ctx.provider;
    mgv = await Mangrove.connect({
      provider: this.test?.parent?.parent?.ctx.providerUrl,
      signer: cleanerSigner,
    });
    cleanerProvider = mgv._provider;
    market = await mgv.market({ base: "TokenA", quote: "TokenB" });

    const testMakerAddress = Mangrove.getAddress(
      "TestMaker",
      mgv._network.name
    );
    testMakerContract = typechain.TestMaker__factory.connect(
      testMakerAddress,
      makerSigner
    );
  });

  afterEach(async function () {
    market.disconnect();
    mgv.disconnect();
  });

  bookSides.forEach((bookSide) => {
    it(`should clean offer failing to trade 0 wants on the '${bookSide}' offer list`, async function () {
      // Arrange
      const { inboundToken, outboundToken } = getTokens(bookSide);

      await testMakerContract.shouldFail(true).then((tx) => tx.wait());
      await testMakerContract[
        "newOffer(address,address,uint256,uint256,uint256,uint256)"
      ](inboundToken.address, outboundToken.address, 1, 1000000, 100, 1).then(
        (tx) => tx.wait()
      );

      const marketCleaner = new MarketCleaner(market, cleanerProvider);

      const cleanerBalanceBefore = await cleanerProvider.getBalance(
        cleanerSigner.address
      );

      // Act
      await marketCleaner.clean(0);

      // Assert
      // FIXME temp debugging output
      const cleanerBalanceAfter = await cleanerProvider.getBalance(
        cleanerSigner.address
      );
      console.group("cleaner balance");
      console.log(`before=${cleanerBalanceBefore}`);
      console.log(`after= ${cleanerBalanceAfter}`);
      console.groupEnd();

      return Promise.all([
        // - Offer is not in the 'bookSide' offer list
        expect(market.requestBook()).to.eventually.have.property(bookSide).which
          .is.empty,
        // - Cleaner acct has more ether than before
        //   - Can we calculate exactly what the balance should be? I guess we can extract the gas used from the cleaning transaction - can we also get the bounty?
        // FIXME bounty is currently too small to offset gas cost
        // expect(
        //   cleanerProvider.getBalance(cleanerSigner.address)
        // ).to.eventually.satisfy((balanceAfter: ethers.BigNumber) => {
        //   console.dir(balanceAfter);
        //   return balanceAfter.gt(cleanerBalanceBefore);
        // }
        // ),
      ]);
    });
  });
});
