// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

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

contract NotAdmin {
  Dex dex;
  address base;
  address quote;

  constructor(Dex _dex) {
    dex = _dex;
  }

  function setGasprice(uint value) public {
    dex.setGasprice(value);
  }

  function setFee(uint fee) public {
    dex.setFee(base, quote, fee);
  }

  function setAdmin(address newAdmin) public {
    dex.setAdmin(newAdmin);
  }
}

// In these tests, the testing contract is the market maker.
contract Gatekeeping_Test {
  receive() external payable {}

  Dex dex;
  TestTaker tkr;
  address base;
  address quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    dex = DexSetup.setup(baseT, quoteT);
    tkr = TakerSetup.setup(dex, base, quote);

    address(tkr).transfer(10 ether);

    bool noRevert;
    (noRevert, ) = address(dex).call{value: 10 ether}("");

    baseT.mint(address(this), 1 ether);
    quoteT.mint(address(tkr), 1 ether);

    baseT.approve(address(dex), 1 ether);
    tkr.approve(quoteT, 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Gatekeeping_Test/maker");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(dex), "dex");
    Display.register(address(tkr), "taker");
  }

  function admin_can_set_admin_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try dex.setAdmin(address(notAdmin)) {
      try notAdmin.setAdmin(address(this)) {
        try notAdmin.setGasprice(10000) {
          TestEvents.fail("notAdmin should no longer have admin rights");
        } catch Error(string memory nolonger_admin) {
          TestEvents.revertEq(nolonger_admin, "HasAdmin/adminOnly");
        }
      } catch {
        TestEvents.fail("notAdmin should have been given admin rights");
      }
    } catch {
      TestEvents.fail("failed to pass admin rights");
    }
  }

  function only_admin_can_set_config_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setFee(0) {
      TestEvents.fail(
        "someone other than admin should not be able to set the configuration"
      );
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "HasAdmin/adminOnly");
    }
  }

  bytes reentrancer; // failing call
  bool shouldFail;

  // maker's execute callback for the dex
  function execute(
    address,
    address,
    uint, /* takerWants*/ // silence warning about unused argument
    uint, /*takerGives*/ // silence warning about unused argument
    uint, /* offerGasprice*/ // silence warning about unused argument
    uint /*offerId */ // silence warning about unused argument
  ) external {
    (bool success, bytes memory retdata) = address(dex).call(reentrancer);
    TestEvents.check(
      (success && !shouldFail) || (!success && shouldFail),
      "unexpected result on Dex reentrancy"
    );
  }

  function testGas_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0);
    tkr.take(ofr, 1 ether);
  }

  function newOffer_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0);
    reentrancer = abi.encodeWithSelector(
      Dex.newOffer.selector,
      address(base),
      address(quote),
      1 ether,
      1 ether,
      30_000,
      0
    );
    shouldFail = true;
    bool success = tkr.take(ofr, 1 ether);
    TestEvents.check(success, "Taker failed to take offer");
  }

  function newOffer_on_reentrancy_succeeds_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 200_000, 0);
    reentrancer = abi.encodeWithSelector(
      Dex.newOffer.selector,
      address(quote),
      address(base),
      1 ether,
      1 ether,
      30_000,
      0
    );
    shouldFail = false;
    bool success = tkr.take(ofr, 1 ether);
    TestEvents.check(success, "Taker failed to take offer");
  }

  function cancelOffer_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 300_000, 0);
    reentrancer = abi.encodeWithSelector(
      Dex.cancelOffer.selector,
      address(base),
      address(quote),
      ofr
    );
    shouldFail = true;
    bool success = tkr.take(ofr, 1 ether);
    TestEvents.check(success, "Taker failed to take offer");
  }

  function cancelOffer_on_reentrancy_succeeds_test() public {
    uint ofr = dex.newOffer(quote, base, 1 ether, 1 ether, 300_000, 0);
    reentrancer = abi.encodeWithSelector(
      Dex.cancelOffer.selector,
      address(base),
      address(quote),
      ofr
    );
    shouldFail = false; // should succeed since reentrancy is on a different pair
    bool success = tkr.take(ofr, 1 ether);
    TestEvents.check(success, "Taker failed to take offer");
  }

  // TODO initial offer (B,A) dex should not be reentrant
  function marketOrder_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 500_000, 0);
    reentrancer = abi.encodeWithSelector(
      Dex.simpleMarketOrder.selector,
      address(base),
      address(quote),
      1 ether,
      1 ether
    );
    shouldFail = true;
    bool success = tkr.take(ofr, 0.1 ether);
    TestEvents.check(success, "Taker failed to take offer");
  }

  function marketOrder_on_reentrancy_fails_succeeds_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 1_000_000, 0);
    uint _ofr = dex.newOffer(quote, base, 1 ether, 1 ether, 20_000, 0);
    reentrancer = abi.encodeWithSelector(
      Dex.simpleMarketOrder.selector,
      address(quote),
      address(base),
      0.1 ether,
      0.1 ether
    );
    shouldFail = false;
    bool success = tkr.take(ofr, 0.1 ether);
    TestEvents.check(success, "Taker failed to take offer");

    TestEvents.expectFrom(address(dex));
    emit DexEvents.Success(_ofr, 0.1 ether, 0.1 ether);
  }

  //
  // function internalSnipes_on_reentrancy_test() public {
  //   uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 30_000, 0);
  //   reentrancer = abi.encodeWithSelector(
  //     Dex.snipe.selector,
  //     address(base),
  //     address(quote),
  //     0,
  //     1 ether);
  //   _reentrancer = abi.encodeWithSelector(
  //       Dex.snipe.selector,
  //       address(quote),
  //       address(base),
  //       0,
  //       1 ether);
  //   bool success = tkr.take(ofr, 1 ether);
  //   TestEvents.check(success,"Taker failed to take offer");
  // }

  function newOffer_on_closed_fails_test() public {
    dex.kill();
    try dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0) {
      TestEvents.fail("newOffer should fail on closed market");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/dead");
    }
  }

  function take_on_closed_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0);

    dex.kill();
    try tkr.take(ofr, 1 ether) {
      TestEvents.fail("take offer should fail on closed market");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/dead");
    }
  }

  function newOffer_on_inactive_test() public {
    dex.setActive(base, quote, false);
    try dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0) {
      TestEvents.fail("newOffer should fail on closed market");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/inactive");
    }
  }

  function receive_on_closed_fails_test() public {
    dex.kill();

    (bool success, bytes memory retdata) =
      address(dex).call{value: 10 ether}("");
    if (success) {
      TestEvents.fail("receive() should fail on closed market");
    } else {
      string memory r = string(retdata);
      TestEvents.revertEq(r, "dex/dead");
    }
  }

  function marketOrder_on_closed_fails_test() public {
    dex.kill();
    try tkr.marketOrder(1 ether, 1 ether) {
      TestEvents.fail("marketOrder should fail on closed market");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/dead");
    }
  }

  function snipe_on_closed_fails_test() public {
    dex.kill();
    try tkr.take(0, 1 ether) {
      TestEvents.fail("snipe should fail on closed market");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/dead");
    }
  }

  function withdraw_on_closed_ok_test() public {
    dex.kill();
    dex.withdraw(0.1 ether);
  }

  function cancelOffer_on_closed_ok_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0);
    dex.kill();
    dex.cancelOffer(base, quote, ofr);
  }
}
