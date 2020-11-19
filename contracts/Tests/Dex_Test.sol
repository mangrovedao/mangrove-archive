// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../DexDeployer.sol";
import "../Dex.sol";
import "../DexCommon.sol";
import "../interfaces.sol";
import "hardhat/console.sol";

import "./Toolbox/TestEvents.sol";
import "./Toolbox/TestUtils.sol";
import "./Toolbox/Display.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
import "./Agents/TestMoriartyMaker.sol";
import "./Agents/MakerDeployer.sol";
import "./Agents/TestTaker.sol";

import "./Scenarii/TestCancelOffer.sol";
import "./Scenarii/TestCollectFailingOffer.sol";
import "./Scenarii/TestInsert.sol";
import "./Scenarii/TestSnipe.sol";
import "./Scenarii/TestMoriarty.sol";
import "./Scenarii/TestMarketOrder.sol";

// Pretest libraries are for deploying large contracts independently.
// Otherwise bytecode can be too large. See EIP 170 for more on size limit:
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-170.md

library TokenSetup {
  function setup(string memory name, string memory ticker)
    external
    returns (TestToken)
  {
    return new TestToken(address(this), name, ticker);
  }
}

library DexSetup {
  function setup(TestToken aToken, TestToken bToken)
    external
    returns (Dex dex)
  {
    TestEvents.testNot0x(address(aToken));
    TestEvents.testNot0x(address(bToken));
    DexDeployer deployer = new DexDeployer(address(this));

    deployer.deploy({
      density: 100,
      gasprice: 40 * 10**9,
      gasbase: 30000,
      gasmax: 1000000,
      ofrToken: address(aToken),
      reqToken: address(bToken)
    });
    return deployer.dexes(address(aToken), address(bToken));
  }
}

library MakerSetup {
  function setup(Dex dex, bool shouldFail) external returns (TestMaker) {
    return new TestMaker(dex, shouldFail);
  }
}

library MakerDeployerSetup {
  function setup(Dex dex) external returns (MakerDeployer) {
    TestEvents.testNot0x(address(dex));
    return (new MakerDeployer(dex));
  }
}

library TakerSetup {
  function setup(Dex dex) external returns (TestTaker) {
    TestEvents.testNot0x(address(dex));
    return new TestTaker(dex);
  }
}

contract Dex_Test {
  Dex dex;
  TestTaker taker;
  MakerDeployer makers;
  TestToken aToken;
  TestToken bToken;
  TestUtils.Balances balances;
  uint[] offerOf;

  mapping(uint => mapping(TestUtils.Info => uint)) offers;

  receive() external payable {}

  function saveOffers() internal {
    uint offerId = dex.getBest();
    while (offerId != 0) {
      (Offer memory offer, OfferDetail memory offerDetail) = dex.getOfferInfo(
        offerId,
        true
      );
      offers[offerId][TestUtils.Info.makerWants] = offer.wants;
      offers[offerId][TestUtils.Info.makerGives] = offer.gives;
      offers[offerId][TestUtils.Info.gasreq] = offerDetail.gasreq;
      offerId = offer.next;
    }
  }

  function saveBalances() internal {
    uint[] memory balA = new uint[](makers.length());
    uint[] memory balB = new uint[](makers.length());
    uint[] memory balWei = new uint[](makers.length());
    for (uint i = 0; i < makers.length(); i++) {
      balA[i] = aToken.balanceOf(address(makers.getMaker(i)));
      balB[i] = bToken.balanceOf(address(makers.getMaker(i)));
      balWei[i] = dex.balanceOf(address(makers.getMaker(i)));
    }
    balances = TestUtils.Balances({
      dexBalanceWei: address(dex).balance,
      dexBalanceFees: aToken.balanceOf(address(dex)),
      takerBalanceA: aToken.balanceOf(address(taker)),
      takerBalanceB: bToken.balanceOf(address(taker)),
      takerBalanceWei: dex.balanceOf(address(taker)),
      makersBalanceA: balA,
      makersBalanceB: balB,
      makersBalanceWei: balWei
    });
  }

  function a_deployToken_beforeAll() public {
    //console.log("IN BEFORE ALL");
    aToken = TokenSetup.setup("A", "$A");
    bToken = TokenSetup.setup("B", "$B");

    TestEvents.testNot0x(address(aToken));
    TestEvents.testNot0x(address(bToken));

    Display.register(address(0), "NULL_ADDRESS");
    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Dex_Test");
    Display.register(address(aToken), "aToken");
    Display.register(address(bToken), "bToken");
  }

  function b_deployDex_beforeAll() public {
    dex = DexSetup.setup(aToken, bToken);
    Display.register(address(dex), "dex");
    TestEvents.testNot0x(address(dex));
    dex.setConfig(ConfigKey.fee, 300);
  }

  function c_deployMakersTaker_beforeAll() public {
    makers = MakerDeployerSetup.setup(dex);
    makers.deploy(4);
    for (uint i = 1; i < makers.length(); i++) {
      Display.register(
        address(makers.getMaker(i)),
        Display.append("maker-", Display.uint2str(i))
      );
    }
    Display.register(address(makers.getMaker(0)), "failer");
    taker = TakerSetup.setup(dex);
    Display.register(address(taker), "taker");
  }

  function d_provisionAll_beforeAll() public {
    // low level tranfer because makers needs gas to transfer to each maker
    (bool success, ) = address(makers).call{gas: gasleft(), value: 80 ether}(
      ""
    ); // msg.value is distributed evenly amongst makers
    require(success, "maker transfer");

    for (uint i = 0; i < makers.length(); i++) {
      TestMaker maker = makers.getMaker(i);
      maker.provisionDex(10 ether);
      aToken.mint(address(maker), 5 ether);
      maker.approve(aToken, 5 ether);
    }

    bToken.mint(address(taker), 5 ether);
    taker.approve(bToken, 5 ether);
    taker.approve(aToken, 50 ether);
  }

  function zeroDust_test() public {
    try dex.setConfig(ConfigKey.density, 0)  {
      TestEvents.testFail("zero density should revert");
    } catch Error(
      string memory /*reason*/
    ) {
      TestEvents.testSuccess();
    }
  }

  function a_full_test() public {
    saveBalances();
    offerOf = TestInsert.run(balances, dex, makers, taker, aToken, bToken);
    emit TestEvents.LOG("End of Insert test");
    Display.logOfferBook(dex, 4);

    saveBalances();
    saveOffers();
    TestSnipe.run(balances, offers, dex, makers, taker, aToken, bToken);
    emit TestEvents.LOG("End of Snipe test");
    Display.logOfferBook(dex, 4);

    saveBalances();
    saveOffers();
    TestMarketOrder.run(balances, offers, dex, makers, taker, aToken, bToken);
    emit TestEvents.LOG("End of MarketOrder test");
    Display.logOfferBook(dex, 4);

    saveBalances();
    saveOffers();
    TestCollectFailingOffer.run(
      balances,
      offers,
      dex,
      offerOf[0],
      makers,
      taker,
      aToken,
      bToken
    );
    emit TestEvents.LOG("end of FailingOffer test");
    Display.logOfferBook(dex, 4);
    saveBalances();
    saveOffers();

    TestCancelOffer.run(
      balances,
      offers,
      dex,
      makers.getMaker(0),
      makers.getMaker(1),
      offerOf[1],
      taker,
      aToken,
      bToken
    );

    // test cancel orders
    // test closeMarket
    // test withdraw
    // test reintrant offer
  }

  function b_test() public {
    TestMoriarty.run(dex, taker, aToken, bToken);
    Display.logOfferBook(dex, 3);
  }
}

contract MakerOperations_Test {
  TestToken atk;
  TestToken btk;
  Dex dex;
  TestTaker tkr;
  TestMaker mkr;
  TestMaker mkr2;

  receive() external payable {}

  function a_beforeAll() public {
    atk = TokenSetup.setup("A", "$A");
    btk = TokenSetup.setup("B", "$B");
    dex = DexSetup.setup(atk, btk);
    mkr = MakerSetup.setup(dex, false);
    mkr2 = MakerSetup.setup(dex, false);
    tkr = TakerSetup.setup(dex);

    address(mkr).transfer(10 ether);
    address(mkr2).transfer(10 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "MakerOperations_Test");
    Display.register(address(atk), "$A");
    Display.register(address(btk), "$B");
    Display.register(address(dex), "dex");
    Display.register(address(mkr), "maker");
    Display.register(address(mkr2), "maker2");
    Display.register(address(tkr), "taker");
  }

  function provision_adds_freeWei_and_ethers_test() public {
    uint dex_bal = address(dex).balance;
    uint amt1 = 235;
    uint amt2 = 1.3 ether;

    mkr.provisionDex(amt1);

    TestEvents.testEq(mkr.freeWei(), amt1, "incorrect mkr freeWei amount (1)");
    TestEvents.testEq(
      address(dex).balance,
      dex_bal + amt1,
      "incorrect dex ETH balance (1)"
    );

    mkr.provisionDex(amt2);

    TestEvents.testEq(
      mkr.freeWei(),
      amt1 + amt2,
      "incorrect mkr freeWei amount (2)"
    );
    TestEvents.testEq(
      address(dex).balance,
      dex_bal + amt1 + amt2,
      "incorrect dex ETH balance (2)"
    );
  }

  function withdraw_removes_freeWei_and_ethers_test() public {
    uint dex_bal = address(dex).balance;
    uint amt1 = 0.86 ether;
    uint amt2 = 0.12 ether;

    mkr.provisionDex(amt1);
    mkr.withdrawDex(amt2);

    TestEvents.testEq(
      mkr.freeWei(),
      amt1 - amt2,
      "incorrect mkr freeWei amount"
    );
    TestEvents.testEq(
      address(dex).balance,
      dex_bal + amt1 - amt2,
      "incorrect dex ETH balance"
    );
  }

  function cant_withdraw_too_much_test() public {
    uint amt1 = 6.003 ether;
    mkr.provisionDex(amt1);
    try mkr.withdrawDex(amt1 + 1)  {
      TestEvents.testFail("mkr cannot withdraw more than it has");
    } catch Error(string memory r) {
      TestEvents.testEq(
        r,
        "dex/insufficientProvision",
        "mkr withdraw failed for the wrong reason"
      );
    }
  }

  function cant_create_offer_without_freeWei_test() public {
    try mkr.newOffer(1 ether, 1 ether, 0, 0)  {
      TestEvents.testFail("mkr cannot create offer without provision");
    } catch Error(string memory r) {
      TestEvents.testEq(
        r,
        "dex/insufficientProvision",
        "new offer failed for wrong reason"
      );
    }
  }

  function cancel_restores_balance_test() public {
    mkr.provisionDex(1 ether);
    uint bal = mkr.freeWei();
    mkr.cancelOffer(mkr.newOffer(1 ether, 1 ether, 2300, 0));

    TestEvents.testEq(mkr.freeWei(), bal, "cancel has not restored balance");
  }

  function cant_cancel_wrong_offer_test() public {
    mkr.provisionDex(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 2300, 0);
    try mkr2.cancelOffer(ofr)  {
      TestEvents.testFail("mkr2 should not be able to cancel mkr's offer");
    } catch Error(string memory r) {
      TestEvents.testEq(
        r,
        "dex/cancelOffer/unauthorized",
        "cancel failed for wrong reason"
      );
    }
  }
}
