// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";

import "./Toolbox/TestEvents.sol";
import "./Toolbox/TestUtils.sol";
import "./Toolbox/Display.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestDelegateTaker.sol";
import "./Agents/OfferManager.sol";
import "./Agents/UniSwapMaker.sol";

contract AMM_Test {
  Dex dex;
  Dex invDex;
  TestToken baseT;
  TestToken quoteT;

  receive() external payable {}

  function a_deployToken_beforeAll() public {
    //console.log("IN BEFORE ALL");
    baseT = TokenSetup.setup("A", "$A");
    quoteT = TokenSetup.setup("B", "$B");

    TestEvents.not0x(address(baseT));
    TestEvents.not0x(address(quoteT));

    Display.register(address(0), "NULL_ADDRESS");
    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "AMM_Test");
    Display.register(address(baseT), "baseT");
    Display.register(address(quoteT), "quoteT");
  }

  function b_deployDex_beforeAll() public {
    dex = DexSetup.setup(baseT, quoteT);
    Display.register(address(dex), "Dex");
    TestEvents.not0x(address(dex));
    //dex.setFee(address(baseT), address(quoteT), 300);

    invDex = DexSetup.setup(baseT, quoteT, true);
    Display.register(address(invDex), "InvDex");
    TestEvents.not0x(address(invDex));
    //invDex.setFee(address(baseT), address(quoteT), 300);
  }

  function prepare_offer_manager()
    internal
    returns (
      OfferManager,
      TestDelegateTaker,
      TestDelegateTaker
    )
  {
    OfferManager mgr = new OfferManager(dex, invDex);
    Display.register(address(mgr), "OfrMgr");

    TestDelegateTaker tkr = new TestDelegateTaker(mgr, baseT, quoteT);
    TestDelegateTaker _tkr = new TestDelegateTaker(mgr, quoteT, baseT);
    Display.register(address(tkr), "Taker (A,B)");
    Display.register(address(_tkr), "Taker (B,A)");
    bool noRevert0;
    (noRevert0, ) = address(_tkr).call{value: 1 ether}("");
    bool noRevert1;
    (noRevert1, ) = address(tkr).call{value: 1 ether}("");
    require(noRevert1 && noRevert0);

    TestMaker maker = MakerSetup.setup(dex, address(baseT), address(quoteT));
    Display.register(address(maker), "Maker");
    baseT.mint(address(maker), 10 ether);
    (bool success, ) = address(maker).call{gas: gasleft(), value: 10 ether}("");
    require(success);
    maker.provisionDex(10 ether);
    maker.newOffer({
      wants: 1 ether,
      gives: 0.5 ether,
      gasreq: 50_000,
      pivotId: 0
    });
    maker.newOffer({
      wants: 1 ether,
      gives: 0.8 ether,
      gasreq: 80_000,
      pivotId: 1
    });
    maker.newOffer({
      wants: 0.5 ether,
      gives: 1 ether,
      gasreq: 90_000,
      pivotId: 72
    });
    return (mgr, tkr, _tkr);
  }

  function check_logs(address mgr, bool inverted) internal {
    TestEvents.expectFrom(address(dex));
    emit DexEvents.Success(
      address(baseT),
      address(quoteT),
      3,
      1 ether,
      0.5 ether
    );
    emit DexEvents.RemoveOffer(address(baseT), address(quoteT), 3, false);
    emit DexEvents.Success(
      address(baseT),
      address(quoteT),
      2,
      0.8 ether,
      1 ether
    );
    emit DexEvents.RemoveOffer(address(baseT), address(quoteT), 2, false);
    Dex DEX = dex;
    if (inverted) {
      TestEvents.expectFrom(address(invDex));
      DEX = invDex;
    }
    emit DexEvents.WriteOffer(
      address(quoteT),
      address(baseT),
      address(mgr),
      1.2 ether,
      1.2 ether,
      100_000,
      DEX.config(address(0), address(0)).global.gasprice,
      1, // first offerId of the quote,base pair
      false
    );
    emit DexEvents.Success(
      address(quoteT),
      address(baseT),
      1,
      1.2 ether,
      1.2 ether
    );
    emit DexEvents.RemoveOffer(address(quoteT), address(baseT), 1, false);
    TestEvents.expectFrom(address(dex));
    emit DexEvents.WriteOffer(
      address(baseT),
      address(quoteT),
      mgr,
      0.6 ether,
      0.6 ether,
      100_000,
      dex.config(address(0), address(0)).global.gasprice,
      4, // first offerId of the quote,base pair
      false
    );
  }

  function offer_manager_test() public {
    (OfferManager mgr, TestDelegateTaker tkr, TestDelegateTaker _tkr) =
      prepare_offer_manager();
    quoteT.mint(address(tkr), 5 ether);
    baseT.mint(address(_tkr), 5 ether);

    Display.logOfferBook(dex, address(baseT), address(quoteT), 5);
    Display.logBalances(baseT, quoteT, address(tkr), address(_tkr));

    tkr.delegateOrder(mgr, 3 ether, 3 ether, dex, false); // (A,B) order

    Display.logBalances(baseT, quoteT, address(tkr), address(_tkr));
    Display.logOfferBook(dex, address(baseT), address(quoteT), 5); // taker has more A
    Display.logOfferBook(dex, address(quoteT), address(baseT), 2);
    //Display.logBalances(baseT, quoteT, address(taker));

    _tkr.delegateOrder(mgr, 1.8 ether, 1.8 ether, dex, false); // (B,A) order
    Display.logOfferBook(dex, address(baseT), address(quoteT), 5);
    Display.logOfferBook(dex, address(quoteT), address(baseT), 2);
    Display.logBalances(baseT, quoteT, address(tkr), address(_tkr));

    check_logs(address(mgr), false);
  }

  function inverted_offer_manager_test() public {
    (OfferManager mgr, TestDelegateTaker tkr, TestDelegateTaker _tkr) =
      prepare_offer_manager();

    quoteT.mint(address(tkr), 5 ether);
    //baseT.mint(address(_taker), 5 ether);
    baseT.addAdmin(address(_tkr)); // to test flashloan on the taker side

    Display.logOfferBook(dex, address(baseT), address(quoteT), 5);
    Display.logBalances(baseT, quoteT, address(tkr), address(_tkr));

    tkr.delegateOrder(mgr, 3 ether, 3 ether, dex, true); // (A,B) order, residual posted on invertedDex(B,A)

    Display.logBalances(baseT, quoteT, address(tkr), address(_tkr));
    Display.logOfferBook(dex, address(baseT), address(quoteT), 5); // taker has more A
    Display.logOfferBook(invDex, address(quoteT), address(baseT), 2);
    Display.logBalances(baseT, quoteT, address(tkr));

    _tkr.delegateOrder(mgr, 1.8 ether, 1.8 ether, invDex, false); // (B,A) FlashTaker order
    Display.logOfferBook(dex, address(baseT), address(quoteT), 5);
    Display.logOfferBook(invDex, address(quoteT), address(baseT), 2);
    Display.logBalances(baseT, quoteT, address(tkr), address(_tkr));
    check_logs(address(mgr), true);
  }

  function uniswap_like_maker_test() public {}
}
