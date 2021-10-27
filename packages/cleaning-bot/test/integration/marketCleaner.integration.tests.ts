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
import { ethers } from "ethers";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
import { ethers as hardhatEthers } from "hardhat";
import { Provider } from "@ethersproject/abstract-provider";
import { SignerWithAddress } from "hardhat-deploy-ethers/dist/src/signers";
import { MarketCleaner } from "../../dist/nodejs/MarketCleaner";
import { toWei } from "../util/helpers";

const bookSides: BookSide[] = ["asks", "bids"];

type AccountBalances = {
  ether: ethers.BigNumber;
  tokenA: ethers.BigNumber;
  tokenB: ethers.BigNumber;
};

type Account = {
  name: string;
  address: string;
  signer: SignerWithAddress;
  contracts: {
    // Contracts connected with the signer for setting chain state in test case setup
    mangrove: typechain.Mangrove;
    testMaker: typechain.TestMaker;
    tokenA: typechain.TestTokenWithDecimals;
    tokenB: typechain.TestTokenWithDecimals;
  };
};

type Addresses = {
  mangrove: string;
  testMaker: string;
  tokenA: string;
  tokenB: string;
};

describe("MarketCleaner integration tests", () => {
  let deployer: Account; // Owner of deployed MGV and token contracts
  let maker: Account; // Owner of TestMaker contract
  let cleaner: Account; // Owner of cleaner EOA
  let accounts: Account[]; // All referenced accounts for easy debugging

  let balancesBefore: Map<string, AccountBalances>; // account name |-> balances
  let balancesAfter: Map<string, AccountBalances>; // account name |-> balances

  let testProvider: Provider; // Only used to read state for assertions, not associated with an account
  let cleanerProvider: Provider; // Tied to the cleaner bot's account

  let mgv: Mangrove;
  let market: Market;

  let addresses: Addresses;

  before(async function () {
    addresses = {
      mangrove: (await hardhatEthers.getContract("Mangrove")).address,
      testMaker: (await hardhatEthers.getContract("TestMaker")).address,
      tokenA: (await hardhatEthers.getContract("TokenA")).address,
      tokenB: (await hardhatEthers.getContract("TokenB")).address,
    };
  });

  const getBalances = async (account: Account): Promise<AccountBalances> => {
    return {
      ether: await testProvider.getBalance(account.address),
      tokenA: await account.contracts.tokenA.balanceOf(account.address),
      tokenB: await account.contracts.tokenB.balanceOf(account.address),
    };
  };

  const initContractsForSigner = async (signer: ethers.Signer) => {
    return {
      mangrove: typechain.Mangrove__factory.connect(addresses.mangrove, signer),
      testMaker: typechain.TestMaker__factory.connect(
        addresses.testMaker,
        signer
      ),
      tokenA: typechain.TestTokenWithDecimals__factory.connect(
        addresses.tokenA,
        signer
      ),
      tokenB: typechain.TestTokenWithDecimals__factory.connect(
        addresses.tokenB,
        signer
      ),
    };
  };

  const initAccount = async (name: string) => {
    const signer = await hardhatEthers.getNamedSigner(name);
    const account = {
      name: name,
      address: signer.address,
      signer: signer,
      contracts: await initContractsForSigner(signer),
    };
    accounts.push(account);
    return account;
  };

  const initAccounts = async () => {
    accounts = [];
    deployer = await initAccount("deployer");
    maker = await initAccount("maker");
    cleaner = await initAccount("cleaner");
  };

  const setBalances = async (balances: Map<string, AccountBalances>) => {
    for (const account of accounts) {
      balances.set(account.name, await getBalances(account));
    }
  };

  const captureBalancesBefore = async () => {
    balancesBefore = new Map<string, AccountBalances>();
    await setBalances(balancesBefore);
  };

  const captureBalancesAfter = async () => {
    balancesAfter = new Map<string, AccountBalances>();
    await setBalances(balancesAfter);
  };

  const getTokens = (bookSide: BookSide) => {
    return {
      inboundToken: bookSide === "asks" ? market.base : market.quote,
      outboundToken: bookSide === "asks" ? market.quote : market.base,
    };
  };

  beforeEach(async function () {
    testProvider = new ethers.providers.JsonRpcProvider(
      this.test?.parent?.parent?.ctx.providerUrl
    );

    await initAccounts();

    // Turn up the Mangrove gasprice to increase the bounty
    await deployer.contracts.mangrove.setGasprice(10).then((tx) => tx.wait());

    await deployer.contracts.tokenA.mint(maker.address, toWei(10));
    await deployer.contracts.tokenB.mint(maker.address, toWei(10));

    await maker.contracts.tokenA.approve(addresses.mangrove, toWei(100));

    await captureBalancesBefore();

    mgv = await Mangrove.connect({
      provider: this.test?.parent?.parent?.ctx.providerUrl,
      signer: cleaner.signer,
    });
    cleanerProvider = mgv._provider;
    market = await mgv.market({ base: "TokenA", quote: "TokenB" });
  });

  afterEach(async function () {
    market.disconnect();
    mgv.disconnect();

    await captureBalancesAfter();

    for (const account of accounts) {
      console.group(`${account.name} balances`);
      console.group("Before");
      console.dir(balancesBefore.get(account.name));
      console.groupEnd();
      console.group("After");
      console.dir(balancesAfter.get(account.name));
      console.groupEnd();
      console.groupEnd();
    }
  });

  bookSides.forEach((bookSide) => {
    it(`should clean offer failing to trade 0 wants on the '${bookSide}' offer list`, async function () {
      // Arrange
      const { inboundToken, outboundToken } = getTokens(bookSide);

      await maker.contracts.testMaker.shouldFail(true).then((tx) => tx.wait());
      await maker.contracts.testMaker[
        "newOffer(address,address,uint256,uint256,uint256,uint256)"
      ](inboundToken.address, outboundToken.address, 1, 1000000, 1000, 1) // (base address, quote address, wants, gives, gasreq, pivotId)
        .then((tx) => tx.wait());

      const marketCleaner = new MarketCleaner(market, cleanerProvider);

      // Act
      await marketCleaner.clean(0);

      // Assert
      return Promise.all([
        expect(market.requestBook()).to.eventually.have.property(bookSide).which
          .is.empty,
        expect(testProvider.getBalance(cleaner.address)).to.eventually.satisfy(
          (balanceAfter: ethers.BigNumber) =>
            balanceAfter.gt(balancesBefore.get(cleaner.name)!.ether)
        ),
      ]);
    });

    // it(`should not clean offer suceeding to trade 0 wants on the '${bookSide}' offer list`, async function () {
    //   // Arrange
    //   const { inboundToken, outboundToken } = getTokens(bookSide);

    //   await testMakerContract.shouldFail(false).then((tx) => tx.wait());
    //   await testMakerContract[
    //     "newOffer(address,address,uint256,uint256,uint256,uint256)"
    //   ](inboundToken.address, outboundToken.address, 1, 1000000, 1000, 1) // (base address, quote address, wants, gives, gasreq, pivotId)
    //     .then((tx) => tx.wait());

    //   const marketCleaner = new MarketCleaner(market, cleanerProvider);

    //   // Act
    //   await marketCleaner.clean(0);

    //   // Assert
    //   return Promise.all([
    //     expect(market.requestBook())
    //       .to.eventually.have.property(bookSide)
    //       .which.has.lengthOf(1),
    //     expect(testProvider.getBalance(cleaner.address)).to.eventually.eq(
    //       cleanerBalancesBefore.ether
    //     ),
    //   ]);
    // });
  });
});
