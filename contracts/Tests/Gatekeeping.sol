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
  TestMaker mkr;
  address base;
  address quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    dex = DexSetup.setup(baseT, quoteT);
    tkr = TakerSetup.setup(dex, base, quote);
    mkr = MakerSetup.setup(dex, quote, base);

    address(tkr).transfer(10 ether);
    address(mkr).transfer(10 ether);

    bool noRevert;
    (noRevert, ) = address(dex).call{value: 10 ether}("");

    mkr.provisionDex(5 ether);

    baseT.mint(address(this), 2 ether);
    quoteT.mint(address(tkr), 1 ether);
    quoteT.mint(address(mkr), 1 ether);

    baseT.approve(address(dex), 1 ether);
    tkr.approve(quoteT, 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Gatekeeping_Test/maker");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(dex), "dex");
    Display.register(address(tkr), "taker[$A,$B]");
    Display.register(address(mkr), "maker[$B,$A]");
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

  bytes callback;

  // maker's execute callback for the dex
  function execute(
    address,
    address,
    uint takerWants,
    uint,
    address taker,
    uint,
    uint
  ) external {
    IERC20(base).transfer(taker, takerWants);
    bool success;
    (success, ) = address(this).call(callback);
  }

  function testGas_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0);
    tkr.take(ofr, 1 ether);
  }

  function newOfferKO() external {
    try dex.newOffer(base, quote, 1 ether, 1 ether, 30_000, 0) {
      TestEvents.fail("newOffer on same pair should fail");
    } catch Error(string memory reason) {
      TestEvents.revertEq(reason, "dex/reentrancyLocked");
    }
  }

  function updateOfferKO(uint ofr) external {
    try dex.updateOffer(base, quote, 1 ether, 2 ether, 35_000, 0, ofr) {
      TestEvents.fail("update offer on same pair should fail");
    } catch Error(string memory reason) {
      TestEvents.revertEq(reason, "dex/reentrancyLocked");
    }
  }

  function updateOfferOK(uint ofr) external {
    try dex.updateOffer(base, quote, 1 ether, 2 ether, 35_000, 0, ofr) {
      TestEvents.succeed();
    } catch {
      TestEvents.fail("update offer on different pair should succeed");
    }
  }

  function newOffer_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0);
    callback = abi.encodeWithSelector(this.newOfferKO.selector);
    tkr.take(ofr, 1 ether);
  }

  function updateOffer_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0);
    callback = abi.encodeWithSelector(this.updateOfferKO.selector, ofr);
    tkr.take(ofr, 1 ether);
  }

  function updateOffer_on_reentrancy_succeeds_test() public {
    uint ofr = dex.newOffer(quote, base, 1 ether, 1 ether, 100_000, 0);
    uint _ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0);
    callback = abi.encodeWithSelector(this.updateOfferOK.selector, _ofr);
    tkr.take(ofr, 1 ether);
  }

  function newOfferOK() external {
    try dex.newOffer(quote, base, 1 ether, 1 ether, 30_000, 0) {
      // all good
    } catch {
      TestEvents.fail("newOffer on swapped pair should work");
    }
  }

  function newOffer_on_reentrancy_succeeds_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0);
    callback = abi.encodeWithSelector(this.newOfferOK.selector);
    tkr.take(ofr, 1 ether);
  }

  function cancelOfferKO(uint id) external {
    try dex.cancelOffer(base, quote, id, false) {
      TestEvents.fail("cancelOffer on same pair should fail");
    } catch Error(string memory reason) {
      TestEvents.revertEq(reason, "dex/reentrancyLocked");
    }
  }

  function cancelOffer_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0);
    callback = abi.encodeWithSelector(this.cancelOfferKO.selector, ofr);
    tkr.take(ofr, 1 ether);
  }

  function cancelOfferOK(uint id) external {
    try dex.cancelOffer(quote, base, id, false) {
      // all good
    } catch {
      TestEvents.fail("cancelOffer on swapped pair should work");
    }
  }

  function cancelOffer_on_reentrancy_succeeds_test() public {
    uint dual_ofr = dex.newOffer(quote, base, 1 ether, 1 ether, 90_000, 0);
    callback = abi.encodeWithSelector(this.cancelOfferOK.selector, dual_ofr);

    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 90_000, 0);
    tkr.take(ofr, 1 ether);
  }

  function marketOrderKO() external {
    try dex.simpleMarketOrder(base, quote, 0.2 ether, 0.2 ether) {
      TestEvents.fail("marketOrder on same pair should fail");
    } catch Error(string memory reason) {
      TestEvents.revertEq(reason, "dex/reentrancyLocked");
    }
  }

  function marketOrder_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0);
    callback = abi.encodeWithSelector(this.marketOrderKO.selector);
    tkr.take(ofr, 0.1 ether);
  }

  function marketOrderOK() external {
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    try dex.simpleMarketOrder(quote, base, 0.2 ether, 0.2 ether) {
      // all good
    } catch {
      TestEvents.fail("marketOrder on swapped pair should work");
    }
  }

  function marketOrder_on_reentrancy_succeeds_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 190_000, 0);
    callback = abi.encodeWithSelector(this.marketOrderOK.selector);
    tkr.take(ofr, 0.1 ether);
  }

  function snipeKO(uint id) external {
    try
      dex.snipe(base, quote, id, 1 ether, type(uint96).max, type(uint24).max)
    {
      TestEvents.fail("snipe on same pair should fail");
    } catch Error(string memory reason) {
      TestEvents.revertEq(reason, "dex/reentrancyLocked");
    }
  }

  function snipe_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 30_000, 0);
    callback = abi.encodeWithSelector(this.snipeKO.selector);
    tkr.take(ofr, 0.1 ether);
  }

  function snipeOK(uint id) external {
    try
      dex.snipe(quote, base, id, 1 ether, type(uint96).max, type(uint24).max)
    {
      // all good
    } catch {
      TestEvents.fail("snipe on swapped pair should work");
    }
  }

  function internalSnipes_on_reentrancy_succeeds_test() public {
    uint dual_ofr = mkr.newOffer(1 ether, 1 ether, 30_000, 0);
    callback = abi.encodeWithSelector(this.snipeOK.selector, dual_ofr);

    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 190_000, 0);
    tkr.take(ofr, 0.1 ether);
  }

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

  function newOffer_on_inactive_fails_test() public {
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
    dex.cancelOffer(base, quote, ofr, false);
  }

  function updateOffer_on_closed_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0);
    dex.kill();
    try dex.updateOffer(base, quote, 1 ether, 1 ether, 0, 0, ofr) {
      TestEvents.fail("update offer should fail on closed market");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/dead");
    }
  }

  function updateOffer_on_inactive_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0);
    dex.setActive(base, quote, false);
    try dex.updateOffer(base, quote, 1 ether, 1 ether, 0, 0, ofr) {
      TestEvents.fail("update offer should fail on inactive market");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/inactive");
    }
  }
}
