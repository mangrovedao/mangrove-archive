// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

//import "../Dex.sol";
//import "../DexCommon.sol";
//import "../interfaces.sol";
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
import "./Scenarii/TestFailingMarketOrder.sol";
import "./Scenarii/TestMarketOrder.sol";

// Pretest libraries are for deploying large contracts independently.
// Otherwise bytecode can be too large. See EIP 170 for more on size limit:
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-170.md

contract Scenarii_Test {
  Dex dex;
  TestTaker taker;
  MakerDeployer makers;
  TestToken base;
  TestToken quote;
  TestUtils.Balances balances;
  uint[] offerOf;

  mapping(uint => mapping(TestUtils.Info => uint)) offers;

  receive() external payable {}

  function saveOffers() internal {
    uint offerId = dex.bests(address(base), address(quote));
    while (offerId != 0) {
      (DC.Offer memory offer, DC.OfferDetail memory offerDetail) =
        dex.getOfferInfo(address(base), address(quote), offerId, true);
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
      balA[i] = base.balanceOf(address(makers.getMaker(i)));
      balB[i] = quote.balanceOf(address(makers.getMaker(i)));
      balWei[i] = dex.balanceOf(address(makers.getMaker(i)));
    }
    balances = TestUtils.Balances({
      dexBalanceWei: address(dex).balance,
      dexBalanceFees: base.balanceOf(TestUtils.adminOf(dex)),
      takerBalanceA: base.balanceOf(address(taker)),
      takerBalanceB: quote.balanceOf(address(taker)),
      takerBalanceWei: dex.balanceOf(address(taker)),
      makersBalanceA: balA,
      makersBalanceB: balB,
      makersBalanceWei: balWei
    });
  }

  function a_deployToken_beforeAll() public {
    //console.log("IN BEFORE ALL");
    base = TokenSetup.setup("A", "$A");
    quote = TokenSetup.setup("B", "$B");

    TestEvents.not0x(address(base));
    TestEvents.not0x(address(quote));

    Display.register(address(0), "NULL_ADDRESS");
    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Dex_Test");
    Display.register(address(base), "base");
    Display.register(address(quote), "quote");
  }

  function b_deployDex_beforeAll() public {
    dex = DexSetup.setup(base, quote);
    Display.register(address(dex), "dex");
    TestEvents.not0x(address(dex));
    dex.setFee(address(base), address(quote), 300);
  }

  function c_deployMakersTaker_beforeAll() public {
    makers = MakerDeployerSetup.setup(dex, address(base), address(quote));
    makers.deploy(4);
    for (uint i = 1; i < makers.length(); i++) {
      Display.register(
        address(makers.getMaker(i)),
        Display.append("maker-", Display.uint2str(i))
      );
    }
    Display.register(address(makers.getMaker(0)), "failer");
    taker = TakerSetup.setup(dex, address(base), address(quote));
    Display.register(address(taker), "taker");
  }

  function d_provisionAll_beforeAll() public {
    // low level tranfer because makers needs gas to transfer to each maker
    (bool success, ) =
      address(makers).call{gas: gasleft(), value: 80 ether}(""); // msg.value is distributed evenly amongst makers
    require(success, "maker transfer");

    for (uint i = 0; i < makers.length(); i++) {
      TestMaker maker = makers.getMaker(i);
      maker.provisionDex(10 ether);
      base.mint(address(maker), 5 ether);
    }

    quote.mint(address(taker), 5 ether);
    taker.approve(quote, 5 ether);
    taker.approve(base, 50 ether);
    saveBalances();
  }

  function zeroDust_test() public {
    try dex.setDensity(address(base), address(quote), 0) {
      TestEvents.fail("zero density should revert");
    } catch Error(
      string memory /*reason*/
    ) {
      TestEvents.succeed();
    }
  }

  function snipe_insert_and_fail_test() public {
    //TestEvents.logString("=== Insert test ===", 0);
    offerOf = TestInsert.run(balances, dex, makers, taker, base, quote);
    //Display.printOfferBook(dex);
    Display.logOfferBook(dex, address(base), address(quote), 4);

    //TestEvents.logString("=== Snipe test ===", 0);
    saveBalances();
    saveOffers();
    TestSnipe.run(balances, offers, dex, makers, taker, base, quote);
    Display.logOfferBook(dex, address(base), address(quote), 4);

    //TestEvents.logString("=== Market order test ===", 0);
    saveBalances();
    saveOffers();
    TestMarketOrder.run(balances, offers, dex, makers, taker, base, quote);
    Display.logOfferBook(dex, address(base), address(quote), 4);

    //TestEvents.logString("=== Failling offer test ===", 0);
    saveBalances();
    saveOffers();
    TestCollectFailingOffer.run(
      balances,
      offers,
      dex,
      offerOf[0],
      makers,
      taker,
      base,
      quote
    );
    Display.logOfferBook(dex, address(base), address(quote), 4);
    saveBalances();
    saveOffers();
  }
}

contract DeepCollect_Test {
  TestToken base;
  TestToken quote;
  Dex dex;
  TestTaker tkr;
  TestMoriartyMaker evil;

  receive() external payable {}

  function a_beforeAll() public {
    base = TokenSetup.setup("A", "$A");
    quote = TokenSetup.setup("B", "$B");
    dex = DexSetup.setup(base, quote);
    tkr = TakerSetup.setup(dex, address(base), address(quote));

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "DeepCollect_Tester");
    Display.register(address(base), "$A");
    Display.register(address(quote), "$B");
    Display.register(address(dex), "dex");
    Display.register(address(tkr), "taker");

    quote.mint(address(tkr), 5 ether);
    tkr.approve(quote, 20 ether);
    tkr.approve(base, 20 ether);

    evil = new TestMoriartyMaker(dex, address(base), address(quote));
    Display.register(address(evil), "Moriarty");

    (bool success, ) = address(evil).call{gas: gasleft(), value: 20 ether}("");
    require(success, "maker transfer");
    evil.provisionDex(10 ether);
    base.mint(address(evil), 5 ether);
    evil.approve(base, 5 ether);

    evil.newOffer({
      wants: 1 ether,
      gives: 0.5 ether,
      gasreq: 100000,
      pivotId: 0
    });
  }

  function market_with_failures_test() public {
    //TestEvents.logString("=== DeepCollect test ===", 0);
    TestFailingMarketOrder.moWithFailures(
      dex,
      address(base),
      address(quote),
      tkr
    );
  }

  function punishing_snipes_test() public {
    TestFailingMarketOrder.snipesAndRevert(
      dex,
      address(base),
      address(quote),
      tkr
    );
  }

  function punishing_market_order_test() public {
    TestFailingMarketOrder.moAndRevert(dex, address(base), address(quote), tkr);
  }
}
