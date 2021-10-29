/**
 * Integration tests of MarketCleaner.ts.
 */
import { afterEach, before, beforeEach, describe, it } from "mocha";
import * as chai from "chai";
const { expect } = chai;
import chaiAsPromised from "chai-as-promised";
chai.use(chaiAsPromised);

import { Mangrove, Market } from "@giry/mangrove-js";
import { ethers } from "ethers";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import { Provider } from "@ethersproject/abstract-provider";
import { MarketCleaner } from "../../dist/nodejs/MarketCleaner";
import {
  Account,
  Balances,
  bookSides,
  getAccount,
  logAddresses,
  postNewSucceedingOffer,
  postNewRevertingOffer,
  getBalances,
  logBalances,
  setMgvGasPrice,
  mint,
  approveMgv,
  AccountName,
} from "../util/helpers";

let maker: Account; // Owner of TestMaker contract
let cleaner: Account; // Owner of cleaner EOA
let accounts: Account[]; // All referenced accounts for easy debugging

let balancesBefore: Map<string, Balances>; // account name |-> balances

let testProvider: Provider; // Only used to read state for assertions, not associated with an account
let cleanerProvider: Provider; // Tied to the cleaner bot's account

let mgv: Mangrove;
let market: Market;

describe("MarketCleaner integration tests", () => {
  before(async function () {
    testProvider = new ethers.providers.JsonRpcProvider(
      this.test?.parent?.parent?.ctx.providerUrl
    );
  });

  beforeEach(async function () {
    maker = await getAccount(AccountName.Maker);
    cleaner = await getAccount(AccountName.Cleaner);

    accounts = [maker, cleaner];

    mgv = await Mangrove.connect({
      provider: this.test?.parent?.parent?.ctx.providerUrl,
      signer: cleaner.signer,
    });
    market = await mgv.market({ base: "TokenA", quote: "TokenB" });

    cleanerProvider = mgv._provider;

    // Turn up the Mangrove gasprice to increase the bounty
    await setMgvGasPrice(50);
    await mint(market.base, maker, 10);
    await mint(market.quote, maker, 10);

    await approveMgv(market.base, maker, 100);
    await approveMgv(market.quote, maker, 100);

    balancesBefore = await getBalances(accounts, testProvider);
  });

  afterEach(async function () {
    market.disconnect();
    mgv.disconnect();

    const balancesAfter = await getBalances(accounts, testProvider);
    logBalances(accounts, balancesBefore, balancesAfter);
    logAddresses();
  });

  bookSides.forEach((bookSide) => {
    it(`should clean offer failing to trade 0 wants on the '${bookSide}' offer list`, async function () {
      // Arrange
      await postNewRevertingOffer(market, bookSide, maker);

      const marketCleaner = new MarketCleaner(market, cleanerProvider);

      // Act
      await marketCleaner.clean(0);

      // Assert
      return Promise.all([
        expect(market.requestBook()).to.eventually.have.property(bookSide).which
          .is.empty,
        expect(testProvider.getBalance(cleaner.address)).to.eventually.satisfy(
          (balanceAfter: ethers.BigNumber) =>
            balanceAfter.gt(balancesBefore.get(cleaner.name)?.ether || -1)
        ),
      ]);
    });

    it(`should not clean offer suceeding to trade 0 wants on the '${bookSide}' offer list`, async function () {
      // Arrange
      await postNewSucceedingOffer(market, bookSide, maker);

      const marketCleaner = new MarketCleaner(market, cleanerProvider);

      // Act
      await marketCleaner.clean(0);

      // Assert
      return Promise.all([
        expect(market.requestBook())
          .to.eventually.have.property(bookSide)
          .which.has.lengthOf(1),
        expect(testProvider.getBalance(cleaner.address)).to.eventually.satisfy(
          (balanceAfter: ethers.BigNumber) =>
            balanceAfter.eq(balancesBefore.get(cleaner.name)?.ether || -1)
        ),
      ]);
    });
  });
});
