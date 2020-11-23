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
      (DC.Offer memory offer, DC.OfferDetail memory offerDetail) = dex.getOfferInfo(
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

    TestEvents.not0x(address(aToken));
    TestEvents.not0x(address(bToken));

    Display.register(address(0), "NULL_ADDRESS");
    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Dex_Test");
    Display.register(address(aToken), "aToken");
    Display.register(address(bToken), "bToken");
  }

  function b_deployDex_beforeAll() public {
    dex = DexSetup.setup(aToken, bToken);
    Display.register(address(dex), "dex");
    TestEvents.not0x(address(dex));
    dex.setConfig(DC.ConfigKey.fee, 300);
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
    saveBalances();
  }

  function a_zeroDust_test() public {
    console.log("Starting a test (%d)", gasleft());

    try dex.setConfig(DC.ConfigKey.density, 0)  {
      TestEvents.fail("zero density should revert");
    } catch Error(
      string memory /*reason*/
    ) {
      TestEvents.succeed();
    }
  }

  function b_basic_test() public {
    TestEvents.logString("=== Insert test ===", 0);
    offerOf = TestInsert.run(balances, dex, makers, taker, aToken, bToken);
    TestEvents.logString("End of Insert test", 0);
    //Display.printOfferBook(dex);
    //Display.logOfferBook(dex,4);

    TestEvents.logString("=== Snipe test ===", 0);
    saveBalances();
    saveOffers();
    TestSnipe.run(balances, offers, dex, makers, taker, aToken, bToken);
    TestEvents.logString("End of Snipe test", 0);
    //Display.logOfferBook(dex, 4);

    TestEvents.logString("=== Market order test ===", 0);
    saveBalances();
    saveOffers();
    TestMarketOrder.run(balances, offers, dex, makers, taker, aToken, bToken);
    TestEvents.logString("End of MarketOrder test", 0);
    //Display.logOfferBook(dex, 4);

    TestEvents.logString("=== Failling offer test ===", 0);
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
    TestEvents.logString("end of FailingOffer test", 0);
    //Display.logOfferBook(dex, 4);
    saveBalances();
    saveOffers();

    // TestCancelOffer.run(
    //   balances,
    //   offers,
    //   dex,
    //   makers.getMaker(0),
    //   makers.getMaker(1),
    //   offerOf[1],
    //   taker,
    //   aToken,
    //   bToken
    // );
    //
    // test closeMarket
    // test withdraw
    // test reintrant offer
  }
}

contract DeepCollect_Test {
  TestToken atk;
  TestToken btk;
  Dex dex;
  TestTaker tkr;

  receive() external payable {}

  function a_beforeAll() public {
    atk = TokenSetup.setup("A", "$A");
    btk = TokenSetup.setup("B", "$B");
    dex = DexSetup.setup(atk, btk);
    tkr = TakerSetup.setup(dex);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "DeepCollect_Tester");
    Display.register(address(atk), "$A");
    Display.register(address(btk), "$B");
    Display.register(address(dex), "dex");
    Display.register(address(tkr), "taker");

    btk.mint(address(tkr), 5 ether);
    tkr.approve(btk, 20 ether);
    tkr.approve(atk, 20 ether);
  }

  function deepCollect_test() public {
    TestEvents.logString("=== DeepCollect test ===", 0);
    TestMoriarty.run(dex, tkr, atk, btk);
  }
}
