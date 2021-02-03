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

  function setGovernance(address newGovernance) public {
    dex.setGovernance(newGovernance);
  }

  function kill() public {
    dex.kill();
  }

  function activate(
    address base,
    address quote,
    uint fee,
    uint density,
    uint gasbase
  ) public {
    dex.activate(base, quote, fee, density, gasbase);
  }

  function setGasbase(
    address base,
    address quote,
    uint value
  ) public {
    dex.setGasbase(base, quote, value);
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
contract Gatekeeping_Test is IMaker {
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
    quoteT.approve(address(dex), 1 ether);
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

  /* # Test Config */

  function gov_can_transfer_rights_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    dex.setGovernance(address(notAdmin));

    try dex.setFee(base, quote, 0) {
      TestEvents.fail("testing contracts should no longer be admin");
    } catch {}

    try notAdmin.setFee(base, quote, 0) {} catch {
      TestEvents.fail("notAdmin should have been given admin rights");
    }
  }

  function only_gov_can_set_fee_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setFee(base, quote, 0) {
      TestEvents.fail("nonadmin cannot set fee");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/unauthorized");
    }
  }

  function only_gov_can_set_density_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setDensity(base, quote, 0) {
      TestEvents.fail("nonadmin cannot set density");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/unauthorized");
    }
  }

  function set_zero_density_test() public {
    try dex.setDensity(base, quote, 0) {} catch Error(string memory r) {
      TestEvents.fail("setting density to 0 should work");
    }
  }

  function only_gov_can_kill_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.kill() {
      TestEvents.fail("nonadmin cannot kill");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/unauthorized");
    }
  }

  function killing_updates_config_test() public {
    dex.kill();
    TestEvents.check(
      dex.config(address(0), address(0)).global.dead,
      "dex should be dead "
    );
  }

  function kill_is_idempotent_test() public {
    dex.kill();
    dex.kill();
    TestEvents.check(
      dex.config(address(0), address(0)).global.dead,
      "dex should still be dead"
    );
  }

  function only_gov_can_set_active_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.activate(quote, base, 0, 100, 30_000) {
      TestEvents.fail("nonadmin cannot set active");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/unauthorized");
    }
  }

  function only_gov_can_set_gasprice_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setGasprice(0) {
      TestEvents.fail("nonadmin cannot set gasprice");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/unauthorized");
    }
  }

  function only_gov_can_set_gasmax_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setGasmax(0) {
      TestEvents.fail("nonadmin cannot set gasmax");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/unauthorized");
    }
  }

  function only_gov_can_set_gasbase_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setGasbase(base, quote, 0) {
      TestEvents.fail("nonadmin cannot set gasbase");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/unauthorized");
    }
  }

  function empty_dex_ok_test() public {
    try tkr.marketOrder(0, 0) {} catch {
      TestEvents.fail("market order on empty dex should not fail");
    }
  }

  function set_fee_ceiling_test() public {
    try dex.setFee(base, quote, 501) {} catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/config/fee/<=500");
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
    try dex.setGasprice(uint(type(uint16).max) + 1) {
      TestEvents.fail("gasprice above ceiling should fail");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/config/gasprice/16bits");
    }
  }

  function set_zero_gasbase_test() public {
    try dex.setGasbase(base, quote, 0) {} catch Error(string memory r) {
      TestEvents.fail("setting gasprice to 0 should work");
    }
  }

  function set_gasbase_ceiling_test() public {
    try dex.setGasbase(base, quote, uint(type(uint24).max) + 1) {
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

  function makerWants_wider_than_96_bits_fails_newOffer_test() public {
    try mkr.newOffer(2**96, 1 ether, 10_000, 0) {
      TestEvents.fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/writeOffer/wants/96bits", "wrong revert reason");
    }
  }

  function retractOffer_wrong_owner_fails() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 10_000, 0);
    try dex.retractOffer(base, quote, ofr, false) {
      TestEvents.fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/retractOffer/unauthorized", "wrong revert reason");
    }
  }

  function makerGives_wider_than_96_bits_fails_newOffer_test() public {
    try mkr.newOffer(1, 2**96, 10_000, 0) {
      TestEvents.fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/writeOffer/gives/96bits", "wrong revert reason");
    }
  }

  function makerGasreq_wider_than_24_bits_fails_newOffer_test() public {
    try mkr.newOffer(1, 1, 2**24, 0) {
      TestEvents.fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/writeOffer/gasreq/24bits", "wrong revert reason");
    }
  }

  function makerGasreq_bigger_than_gasmax_fails_newOffer_test() public {
    DexCommon.Config memory cfg = dex.config(base, quote);
    try mkr.newOffer(1, 1, cfg.global.gasmax + 1, 0) {
      TestEvents.fail("Offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/writeOffer/gasreq/tooHigh", "wrong revert reason");
    }
  }

  function makerGasreq_lower_than_density_fails_newOffer_test() public {
    DexCommon.Config memory cfg = dex.config(base, quote);
    try mkr.newOffer(1, 1, cfg.local.density - 1, 0) {
      TestEvents.fail("Offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/writeOffer/density/tooLow", "wrong revert reason");
    }
  }

  function makerGasprice_wider_than_16_bits_fails_newOffer_test() public {
    try mkr.newOffer(1, 1, 1, 2**16, 0) {
      TestEvents.fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/writeOffer/gasprice/16bits", "wrong revert reason");
    }
  }

  function takerWants_wider_than_160_bits_fails_marketOrder_test() public {
    try tkr.marketOrder(2**160, 0) {
      TestEvents.fail("takerWants > 160bits, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/mOrder/takerWants/160bits", "wrong revert reason");
    }
  }

  function takerWants_above_96bits_fails_snipes_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [
      ofr,
      uint(type(uint96).max) + 1,
      type(uint96).max,
      type(uint).max
    ];
    try dex.snipes(base, quote, targets, 0) {
      TestEvents.fail("Snipes with takerWants > 96bits should fail");
    } catch Error(string memory reason) {
      TestEvents.revertEq(reason, "dex/snipes/takerWants/96bits");
    }
  }

  /* # Internal IMaker setup */

  bytes trade_cb;
  bytes posthook_cb;

  // maker's trade fn for the dex
  function makerTrade(DC.SingleOrder calldata order)
    external
    override
    returns (bytes32 ret)
  {
    ret; // silence unused function parameter
    bool success;
    if (trade_cb.length > 0) {
      (success, ) = address(this).call(trade_cb);
      require(success, "makerTrade callback must work");
    }
  }

  function makerPosthook(
    DC.SingleOrder calldata order,
    DC.OrderResult calldata result
  ) external override {
    bool success;
    order; // silence compiler warning
    if (posthook_cb.length > 0) {
      (success, ) = address(this).call(posthook_cb);
      require(result.success, "makerPosthook callback must work");
    }
  }

  /* # Reentrancy */

  /* New Offer failure */

  function newOfferKO() external {
    try dex.newOffer(base, quote, 1 ether, 1 ether, 30_000, 0, 0) {
      TestEvents.fail("newOffer on same pair should fail");
    } catch Error(string memory reason) {
      TestEvents.revertEq(reason, "dex/reentrancyLocked");
    }
  }

  function newOffer_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.newOfferKO.selector);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
  }

  /* New Offer success */

  // ! may be called with inverted _base and _quote
  function newOfferOK(address _base, address _quote) external {
    dex.newOffer(_base, _quote, 1 ether, 1 ether, 30_000, 0, 0);
  }

  function newOffer_on_reentrancy_succeeds_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 200_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.newOfferOK.selector, quote, base);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(dex.bests(quote, base) == 1, "newOffer on swapped pair must work");
  }

  function newOffer_on_posthook_succeeds_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 200_000, 0, 0);
    posthook_cb = abi.encodeWithSelector(this.newOfferOK.selector, base, quote);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(dex.bests(base, quote) == 2, "newOffer on posthook must work");
  }

  /* Update offer failure */

  function updateOfferKO(uint ofr) external {
    try dex.updateOffer(base, quote, 1 ether, 2 ether, 35_000, 0, 0, ofr) {
      TestEvents.fail("update offer on same pair should fail");
    } catch Error(string memory reason) {
      TestEvents.revertEq(reason, "dex/reentrancyLocked");
    }
  }

  function updateOffer_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.updateOfferKO.selector, ofr);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
  }

  /* Update offer success */

  // ! may be called with inverted _base and _quote
  function updateOfferOK(
    address _base,
    address _quote,
    uint ofr
  ) external {
    dex.updateOffer(_base, _quote, 1 ether, 2 ether, 35_000, 0, 0, ofr);
  }

  function updateOffer_on_reentrancy_succeeds_test() public {
    uint other_ofr = dex.newOffer(quote, base, 1 ether, 1 ether, 100_000, 0, 0);

    trade_cb = abi.encodeWithSelector(
      this.updateOfferOK.selector,
      quote,
      base,
      other_ofr
    );
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 400_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    (, DC.OfferDetail memory od) =
      dex.getOfferInfo(quote, base, other_ofr, true);
    require(od.gasreq == 35_000, "updateOffer on swapped pair must work");
  }

  function updateOffer_on_posthook_succeeds_test() public {
    uint other_ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);
    posthook_cb = abi.encodeWithSelector(
      this.updateOfferOK.selector,
      base,
      quote,
      other_ofr
    );
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 300_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    (, DC.OfferDetail memory od) =
      dex.getOfferInfo(base, quote, other_ofr, true);
    require(od.gasreq == 35_000, "updateOffer on posthook must work");
  }

  /* Cancel Offer failure */

  function retractOfferKO(uint id) external {
    try dex.retractOffer(base, quote, id, false) {
      TestEvents.fail("retractOffer on same pair should fail");
    } catch Error(string memory reason) {
      TestEvents.revertEq(reason, "dex/reentrancyLocked");
    }
  }

  function retractOffer_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.retractOfferKO.selector, ofr);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
  }

  /* Cancel Offer success */

  function retractOfferOK(
    address _base,
    address _quote,
    uint id
  ) external {
    dex.retractOffer(_base, _quote, id, false);
  }

  function retractOffer_on_reentrancy_succeeds_test() public {
    uint other_ofr = dex.newOffer(quote, base, 1 ether, 1 ether, 90_000, 0, 0);
    trade_cb = abi.encodeWithSelector(
      this.retractOfferOK.selector,
      quote,
      base,
      other_ofr
    );

    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 90_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(
      dex.bests(quote, base) == 0,
      "retractOffer on swapped pair must work"
    );
  }

  function retractOffer_on_posthook_succeeds_test() public {
    uint other_ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 190_000, 0, 0);
    posthook_cb = abi.encodeWithSelector(
      this.retractOfferOK.selector,
      base,
      quote,
      other_ofr
    );

    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 90_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(dex.bests(base, quote) == 0, "retractOffer on posthook must work");
  }

  /* Market Order failure */

  function marketOrderKO() external {
    try dex.simpleMarketOrder(base, quote, 0.2 ether, 0.2 ether) {
      TestEvents.fail("marketOrder on same pair should fail");
    } catch Error(string memory reason) {
      TestEvents.revertEq(reason, "dex/reentrancyLocked");
    }
  }

  function marketOrder_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.marketOrderKO.selector);
    require(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
  }

  /* Market Order Success */

  function marketOrderOK(address _base, address _quote) external {
    try
      dex.simpleMarketOrder(_base, _quote, 0.5 ether, 0.5 ether)
    {} catch Error(string memory r) {
      console.log("ERR", r);
    }
  }

  function marketOrder_on_reentrancy_succeeds_test() public {
    console.log(
      "dual mkr offer",
      dual_mkr.newOffer(0.5 ether, 0.5 ether, 30_000, 0)
    );
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 392_000, 0, 0);
    console.log("normal offer", ofr);
    trade_cb = abi.encodeWithSelector(this.marketOrderOK.selector, quote, base);
    require(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
    require(
      dex.bests(quote, base) == 0,
      "2nd market order must have emptied dex"
    );
  }

  function marketOrder_on_posthook_succeeds_test() public {
    uint ofr = dex.newOffer(base, quote, 0.5 ether, 0.5 ether, 500_000, 0, 0);
    dex.newOffer(base, quote, 0.5 ether, 0.5 ether, 200_000, 0, 0);
    posthook_cb = abi.encodeWithSelector(
      this.marketOrderOK.selector,
      base,
      quote
    );
    require(tkr.take(ofr, 0.6 ether), "take must succeed or test is void");
    require(
      dex.bests(base, quote) == 0,
      "2nd market order must have emptied dex"
    );
  }

  /* Snipe failure */

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
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 60_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.snipeKO.selector, ofr);
    require(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
  }

  /* Snipe success */

  function snipeOK(
    address _base,
    address _quote,
    uint id
  ) external {
    dex.snipe(_base, _quote, id, 1 ether, type(uint96).max, type(uint24).max);
  }

  function snipes_on_reentrancy_succeeds_test() public {
    uint other_ofr = dual_mkr.newOffer(1 ether, 1 ether, 30_000, 0);
    trade_cb = abi.encodeWithSelector(
      this.snipeOK.selector,
      quote,
      base,
      other_ofr
    );

    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 190_000, 0, 0);
    require(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
    require(dex.bests(quote, base) == 0, "snipe in swapped pair must work");
  }

  function snipes_on_posthook_succeeds_test() public {
    uint other_ofr = mkr.newOffer(1 ether, 1 ether, 30_000, 0);
    posthook_cb = abi.encodeWithSelector(
      this.snipeOK.selector,
      base,
      quote,
      other_ofr
    );

    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 190_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(dex.bests(base, quote) == 0, "snipe in posthook must work");
  }

  function newOffer_on_closed_fails_test() public {
    dex.kill();
    try dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0, 0) {
      TestEvents.fail("newOffer should fail on closed market");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/dead");
    }
  }

  /* # Dex closed/inactive */

  function take_on_closed_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0, 0);

    dex.kill();
    try tkr.take(ofr, 1 ether) {
      TestEvents.fail("take offer should fail on closed market");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/dead");
    }
  }

  function newOffer_on_inactive_fails_test() public {
    dex.deactivate(base, quote);
    try dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0, 0) {
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

  function retractOffer_on_closed_ok_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0, 0);
    dex.kill();
    dex.retractOffer(base, quote, ofr, false);
  }

  function updateOffer_on_closed_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0, 0);
    dex.kill();
    try dex.updateOffer(base, quote, 1 ether, 1 ether, 0, 0, 0, ofr) {
      TestEvents.fail("update offer should fail on closed market");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/dead");
    }
  }

  function updateOffer_on_inactive_fails_test() public {
    uint ofr = dex.newOffer(base, quote, 1 ether, 1 ether, 0, 0, 0);
    dex.deactivate(base, quote);
    try dex.updateOffer(base, quote, 1 ether, 1 ether, 0, 0, 0, ofr) {
      TestEvents.fail("update offer should fail on inactive market");
    } catch Error(string memory r) {
      TestEvents.revertEq(r, "dex/inactive");
    }
  }
}
