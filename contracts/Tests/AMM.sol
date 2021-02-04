// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "hardhat/console.sol";
import "../DexPack.sol";
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
    maker.approveDex(baseT, 10 ether);
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
    emit DexEvents.Success(
      address(baseT),
      address(quoteT),
      2,
      0.8 ether,
      1 ether
    );
    Dex DEX = dex;
    if (inverted) {
      TestEvents.expectFrom(address(invDex));
      DEX = invDex;
    }
    emit DexEvents.WriteOffer(
      address(quoteT),
      address(baseT),
      address(mgr),
      DexPack.writeOffer_pack(
        1.2 ether,
        1.2 ether,
        DEX.config(address(0), address(0)).global.gasprice,
        100_000,
        1
      )
    );
    emit DexEvents.Success(
      address(quoteT),
      address(baseT),
      1,
      1.2 ether,
      1.2 ether
    );
    TestEvents.expectFrom(address(dex));

    emit DexEvents.WriteOffer(
      address(baseT),
      address(quoteT),
      mgr,
      DexPack.writeOffer_pack(
        0.6 ether,
        0.6 ether,
        dex.config(address(0), address(0)).global.gasprice,
        100_000,
        4
      )
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

  function uniswap_like_maker_test() public {
    UniSwapMaker amm = new UniSwapMaker(dex, 100, 3);
    Display.register(address(amm), "UnisWapMaker");
    Display.register(address(this), "TestRunner");
    quoteT.mint(address(amm), 1000 ether);
    baseT.mint(address(amm), 1000 ether);
    dex.fund{value: 5 ether}(address(amm));
    quoteT.mint(address(this), 5 ether);
    quoteT.approve(address(dex), 2**256 - 1);
    baseT.mint(address(this), 5 ether);
    baseT.approve(address(dex), 2**256 - 1);

    amm.newOffer(address(baseT), address(quoteT));

    Display.logOfferBook(dex, address(baseT), address(quoteT), 1);
    Display.logOfferBook(dex, address(quoteT), address(baseT), 1);

    uint gas = gasleft();
    (uint takerGot, uint takerGave) =
      dex.simpleMarketOrder(address(baseT), address(quoteT), 3, 2**256 - 1);
    uint _gas = gas - gasleft();
    console.log("Gas used in the order:", _gas);

    Display.logOfferBook(dex, address(baseT), address(quoteT), 1);
    Display.logOfferBook(dex, address(quoteT), address(baseT), 1);
  }
}
