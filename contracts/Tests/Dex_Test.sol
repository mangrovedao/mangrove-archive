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

library DexPre0 {
  function setup() external returns (TestToken, TestToken) {
    return (
      new TestToken(address(this), "A", "$A"),
      new TestToken(address(this), "B", "$B")
    );
  }
}

library DexPre1 {
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

library DexPre2 {
  function setup(Dex dex) external returns (MakerDeployer) {
    TestEvents.testNot0x(address(dex));
    return (new MakerDeployer(dex));
  }
}

library DexPre3 {
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
    (aToken, bToken) = DexPre0.setup();

    TestEvents.testNot0x(address(aToken));
    TestEvents.testNot0x(address(bToken));

    Display.register(address(0), "NULL_ADDRESS");
    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Dex_Test");
    Display.register(address(aToken), "aToken");
    Display.register(address(bToken), "bToken");
  }

  function b_deployDex_beforeAll() public {
    dex = DexPre1.setup(aToken, bToken);
    Display.register(address(dex), "dex");
    TestEvents.testNot0x(address(dex));
    dex.setConfig(ConfigKey.fee, 300);
  }

  function c_deployMakersTaker_beforeAll() public {
    makers = DexPre2.setup(dex);
    makers.deploy(4);
    for (uint i = 1; i < makers.length(); i++) {
      Display.register(
        address(makers.getMaker(i)),
        Display.append("maker-", Display.uint2str(i))
      );
    }
    Display.register(address(makers.getMaker(0)), "failer");
    taker = DexPre3.setup(dex);
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
