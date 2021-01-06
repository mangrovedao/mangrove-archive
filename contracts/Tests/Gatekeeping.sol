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

  constructor(Dex _dex) {
    dex = _dex;
  }

  function setGasprice(uint value) public {
    dex.setGasprice(value);
  }

  function setFee(
    address base,
    address quote,
    uint fee
  ) public {
    dex.setFee(base, quote, fee);
  }

  function setAdmin(address newAdmin) public {
    dex.setAdmin(newAdmin);
  }

  function kill() public {
    dex.kill();
  }

  function setActive(
    address base,
    address quote,
    bool value
  ) public {
    dex.setActive(base, quote, value);
  }

  function setGasbase(uint value) public {
    dex.setGasbase(value);
  }

  function setGasmax(uint value) public {
    dex.setGasmax(value);
  }

  function setDensity(
    address base,
    address quote,
    uint value
  ) public {
    dex.setDensity(base, quote, value);
  }
}

// In these tests, the testing contract is the market maker.
contract Gatekeeping_Test {
  receive() external payable {}

  Dex dex;
  TestTaker tkr;
  TestMaker mkr;
  TestMaker dual_mkr;
  address base;
  address quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    dex = DexSetup.setup(baseT, quoteT);
    tkr = TakerSetup.setup(dex, base, quote);
    mkr = MakerSetup.setup(dex, base, quote);
    dual_mkr = MakerSetup.setup(dex, quote, base);

    address(tkr).transfer(10 ether);
    address(mkr).transfer(10 ether);
    address(dual_mkr).transfer(10 ether);

    bool noRevert;
    (noRevert, ) = address(dex).call{value: 10 ether}("");

    mkr.provisionDex(5 ether);
    dual_mkr.provisionDex(5 ether);

    baseT.mint(address(this), 2 ether);
    quoteT.mint(address(tkr), 1 ether);
    quoteT.mint(address(mkr), 1 ether);
    baseT.mint(address(dual_mkr), 1 ether);

    baseT.approve(address(dex), 1 ether);
    tkr.approveDex(quoteT, 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Gatekeeping_Test/maker");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(dex), "dex");
    Display.register(address(tkr), "taker[$A,$B]");
    Display.register(address(dual_mkr), "maker[$B,$A]");
    Display.register(address(mkr), "maker[$A,$B]");
  }

  function admin_can_transfer_rights_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    dex.setAdmin(address(notAdmin));

    try dex.setFee(base, quote, 0) {
      TestEvents.fail("testing contracts should no longer be admin");
    } catch {}

    try notAdmin.setFee(base, quote, 0) {} catch {
      TestEvents.fail("notAdmin should have been given admin rights");
    }
  }

  function only_admin_can_set_fee_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setFee(base, quote, 0) {
      TestEvents.fail("nonadmin cannot set fee");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "HasAdmin/adminOnly");
    }
  }

  function only_admin_can_set_density_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setDensity(base, quote, 0) {
      TestEvents.fail("nonadmin cannot set density");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "HasAdmin/adminOnly");
    }
  }

  function only_admin_can_kill_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.kill() {
      TestEvents.fail("nonadmin cannot kill");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "HasAdmin/adminOnly");
    }
  }

  function only_admin_can_set_active_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setActive(quote, base, true) {
      TestEvents.fail("nonadmin cannot set active");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "HasAdmin/adminOnly");
    }
  }

  function only_admin_can_set_gasprice_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setGasprice(0) {
      TestEvents.fail("nonadmin cannot set gasprice");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "HasAdmin/adminOnly");
    }
  }

  function only_admin_can_set_gasmax_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setGasmax(0) {
      TestEvents.fail("nonadmin cannot set gasmax");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "HasAdmin/adminOnly");
    }
  }

  function only_admin_can_set_gasbase_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setGasbase(0) {
      TestEvents.fail("nonadmin cannot set gasbase");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "HasAdmin/adminOnly");
    }
  }

  function empty_dex_throws_test() public {
    try tkr.marketOrder(0, 0) {
      TestEvents.fail("market order on empty dex should fail");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/marketOrder/noSuchOffer");
    }
  }

  function set_fee_ceiling_test() public {
    try dex.setFee(base, quote, 501) {} catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/config/fee/<=500");
    }
  }

  function set_density_floor_test() public {
    try dex.setDensity(base, quote, 0) {
      TestEvents.fail("density below floor should fail");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/config/density/>0");
    }
  }

  function set_density_ceiling_test() public {
    try dex.setDensity(base, quote, uint(type(uint32).max) + 1) {
      TestEvents.fail("density above ceiling should fail");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/config/density/32bits");
    }
  }

  function set_gasprice_ceiling_test() public {
    try dex.setGasprice(uint(type(uint48).max) + 1) {
      TestEvents.fail("gasprice above ceiling should fail");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/config/gasprice/48bits");
    }
  }

  function set_gasbase_floor_test() public {
    try dex.setGasbase(0) {
      TestEvents.fail("gasprice below floor should fail");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/config/gasbase/>0");
    }
  }

  function set_gasbase_ceiling_test() public {
    try dex.setGasbase(uint(type(uint24).max) + 1) {
      TestEvents.fail("gasbase above ceiling should fail");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/config/gasbase/24bits");
    }
  }

  function set_gasmax_ceiling_test() public {
    try dex.setGasmax(uint(type(uint24).max) + 1) {
      TestEvents.fail("gasmax above ceiling should fail");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/config/gasmax/24bits");
    }
  }

  function takerWants_wider_than_160_bits_fails_marketOrder_test() public {
    try tkr.marketOrder(2**160, 0) {
      TestEvents.fail("takerWants > 160bits, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/mOrder/takerWants/160bits", "wrong revert reason");
    }
  }

  function takerWants_above_96bits_fails_internalSnipes_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [
      ofr,
      uint(type(uint96).max) + 1,
      type(uint96).max,
      type(uint).max
    ];
    try dex.internalSnipes(base, quote, targets, 0) {
      TestEvents.fail("Snipes with takerWants > 96bits should fail");
    } catch Error(string memory reason) {
      TestEvents.revertEq(reason, "dex/internalSnipes/takerWants/96bits");
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
    dual_mkr.newOffer(1 ether, 1 ether, 100_000, 0);
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
    uint dual_ofr = dual_mkr.newOffer(1 ether, 1 ether, 30_000, 0);
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
