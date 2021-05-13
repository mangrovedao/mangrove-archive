// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "hardhat/console.sol";
import "../../MgvPack.sol";
import "../Toolbox/TestEvents.sol";
import "../Toolbox/TestUtils.sol";
import "../Toolbox/Display.sol";

import "../Agents/TestToken.sol";
import "../Agents/TestDelegateTaker.sol";
import "../Agents/OfferManager.sol";
import "../Agents/UniSwapMaker.sol";

contract AMM_Test {
  Mangrove mgv;
  Mangrove invMgv;
  TestToken tk0;
  TestToken tk1;

  receive() external payable {}

  function a_deployToken_beforeAll() public {
    //console.log("IN BEFORE ALL");
    tk0 = TokenSetup.setup("tk0", "$tk0");
    tk1 = TokenSetup.setup("tk1", "$tk1");

    TestEvents.not0x(address(tk0));
    TestEvents.not0x(address(tk1));

    Display.register(address(0), "NULL_ADDRESS");
    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "AMM_Test");
    Display.register(address(tk0), "tk0");
    Display.register(address(tk1), "tk1");
  }

  function b_deployMgv_beforeAll() public {
    mgv = MgvSetup.setup(tk0, tk1);
    Display.register(address(mgv), "Mgv");
    TestEvents.not0x(address(mgv));
    //mgv.setFee(address(tk0), address(tk1), 300);

    invMgv = MgvSetup.setup(tk0, tk1, true);
    Display.register(address(invMgv), "InvMgv");
    TestEvents.not0x(address(invMgv));
    //invMgv.setFee(address(tk0), address(tk1), 300);
  }

  function prepare_offer_manager()
    internal
    returns (
      OfferManager,
      TestDelegateTaker,
      TestDelegateTaker
    )
  {
    OfferManager mgr = new OfferManager(mgv, invMgv);
    Display.register(address(mgr), "OfrMgr");

    TestDelegateTaker tkr = new TestDelegateTaker(mgr, tk0, tk1);
    TestDelegateTaker _tkr = new TestDelegateTaker(mgr, tk1, tk0);
    Display.register(address(tkr), "Taker (tk0,tk1)");
    Display.register(address(_tkr), "Taker (tk1,tk0)");
    bool noRevert0;
    (noRevert0, ) = address(_tkr).call{value: 1 ether}("");
    bool noRevert1;
    (noRevert1, ) = address(tkr).call{value: 1 ether}("");
    require(noRevert1 && noRevert0);

    TestMaker maker = MakerSetup.setup(mgv, address(tk0), address(tk1));
    Display.register(address(maker), "Maker");
    tk0.mint(address(maker), 10 ether);
    (bool success, ) = address(maker).call{gas: gasleft(), value: 10 ether}("");
    require(success);
    maker.provisionMgv(10 ether);
    maker.approveMgv(tk0, 10 ether);
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
    TestEvents.expectFrom(address(mgv));
    emit MgvEvents.Success(
      address(tk0),
      address(tk1),
      3,
      address(mgr),
      1 ether,
      0.5 ether
    );
    emit MgvEvents.Success(
      address(tk0),
      address(tk1),
      2,
      address(mgr),
      0.8 ether,
      1 ether
    );
    Mangrove MGV = mgv;
    if (inverted) {
      TestEvents.expectFrom(address(invMgv));
      MGV = invMgv;
    }
    emit MgvEvents.WriteOffer(
      address(tk1),
      address(tk0),
      mgr,
      MgvPack.writeOffer_pack(
        1.2 ether,
        1.2 ether,
        MGV.getConfig(address(0), address(0)).global.gasprice,
        100_000,
        1
      )
    );
    emit MgvEvents.Success(
      address(tk1),
      address(tk0),
      1,
      address(mgr),
      1.2 ether,
      1.2 ether
    );
    TestEvents.expectFrom(address(mgv));

    emit MgvEvents.WriteOffer(
      address(tk0),
      address(tk1),
      mgr,
      MgvPack.writeOffer_pack(
        0.6 ether,
        0.6 ether,
        mgv.getConfig(address(0), address(0)).global.gasprice,
        100_000,
        4
      )
    );
  }

  function offer_manager_test() public {
    (OfferManager mgr, TestDelegateTaker tkr, TestDelegateTaker _tkr) =
      prepare_offer_manager();
    tk1.mint(address(tkr), 5 ether);
    tk0.mint(address(_tkr), 5 ether);

    Display.logOfferBook(mgv, address(tk0), address(tk1), 5);
    Display.logBalances(tk0, tk1, address(tkr), address(_tkr));

    tkr.delegateOrder(mgr, 3 ether, 3 ether, mgv, false); // (A,B) order

    Display.logBalances(tk0, tk1, address(tkr), address(_tkr));
    Display.logOfferBook(mgv, address(tk0), address(tk1), 5); // taker has more A
    Display.logOfferBook(mgv, address(tk1), address(tk0), 2);
    //Display.logBalances(tk0, tk1, address(taker));

    _tkr.delegateOrder(mgr, 1.8 ether, 1.8 ether, mgv, false); // (B,A) order
    Display.logOfferBook(mgv, address(tk0), address(tk1), 5);
    Display.logOfferBook(mgv, address(tk1), address(tk0), 2);
    Display.logBalances(tk0, tk1, address(tkr), address(_tkr));

    check_logs(address(mgr), false);
  }

  function inverted_offer_manager_test() public {
    (OfferManager mgr, TestDelegateTaker tkr, TestDelegateTaker _tkr) =
      prepare_offer_manager();

    tk1.mint(address(tkr), 5 ether);
    //tk0.mint(address(_taker), 5 ether);
    tk0.addAdmin(address(_tkr)); // to test flashloan on the taker side

    Display.logOfferBook(mgv, address(tk0), address(tk1), 5);
    Display.logBalances(tk0, tk1, address(tkr), address(_tkr));

    tkr.delegateOrder(mgr, 3 ether, 3 ether, mgv, true); // (A,B) order, residual posted on invertedMgv(B,A)

    Display.logBalances(tk0, tk1, address(tkr), address(_tkr));
    Display.logOfferBook(mgv, address(tk0), address(tk1), 5); // taker has more A
    Display.logOfferBook(invMgv, address(tk1), address(tk0), 2);
    Display.logBalances(tk0, tk1, address(tkr));

    _tkr.delegateOrder(mgr, 1.8 ether, 1.8 ether, invMgv, false); // (B,A) FlashTaker order
    Display.logOfferBook(mgv, address(tk0), address(tk1), 5);
    Display.logOfferBook(invMgv, address(tk1), address(tk0), 2);
    Display.logBalances(tk0, tk1, address(tkr), address(_tkr));
    check_logs(address(mgr), true);
  }

  function uniswap_like_maker_test() public {
    UniSwapMaker amm = new UniSwapMaker(mgv, 100, 3); // creates the amm

    Display.register(address(amm), "UnisWapMaker");
    Display.register(address(this), "TestRunner");

    tk1.mint(address(amm), 1000 ether);
    tk0.mint(address(amm), 500 ether);

    mgv.fund{value: 5 ether}(address(amm));

    tk1.mint(address(this), 5 ether);
    tk1.approve(address(mgv), 2**256 - 1);

    tk0.mint(address(this), 5 ether);
    tk0.approve(address(mgv), 2**256 - 1);

    amm.newMarket(address(tk0), address(tk1));

    Display.logOfferBook(mgv, address(tk0), address(tk1), 1);
    Display.logOfferBook(mgv, address(tk1), address(tk0), 1);

    mgv.marketOrder(address(tk0), address(tk1), 3 ether, 2**256 - 1);

    Display.logOfferBook(mgv, address(tk0), address(tk1), 1);
    Display.logOfferBook(mgv, address(tk1), address(tk0), 1);
  }
}
