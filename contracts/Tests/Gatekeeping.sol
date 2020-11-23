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

contract NotAdmin {
  Dex dex;

  constructor(Dex _dex) {
    dex = _dex;
  }

  function setConfig(ConfigKey key, uint value) public {
    dex.setConfig(key, value);
  }
}

// In these tests, the testing contract is the market maker.
contract Gatekeeping_Test {
  receive() external payable {}

  Dex dex;
  TestTaker tkr;

  function a_beforeAll() public {
    TestToken atk = TokenSetup.setup("A", "$A");
    TestToken btk = TokenSetup.setup("B", "$B");
    dex = DexSetup.setup(atk, btk);
    tkr = TakerSetup.setup(dex);

    address(tkr).transfer(10 ether);

    bool noRevert;
    (noRevert, ) = address(dex).call{value: 10 ether}("");

    atk.mint(address(this), 1 ether);
    btk.mint(address(tkr), 1 ether);

    atk.approve(address(dex), 1 ether);
    tkr.approve(btk, 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Gatekeeping_Test/maker");
    Display.register(address(atk), "$A");
    Display.register(address(btk), "$B");
    Display.register(address(dex), "dex");
    Display.register(address(tkr), "taker");
  }

  function only_admin_can_set_config_test() public {
    NotAdmin notAdmin = new NotAdmin(dex);
    try notAdmin.setConfig(ConfigKey.fee, 0)  {
      TestEvents.fail(
        "someone other than admin should not be able to set the configuration"
      );
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/adminOnly", "wrong revert reason");
    }
  }

  bytes reentrancer;

  // maker's execute callback for the dex
  function execute(
    uint, /* takerWants*/ // silence warning about unused argument
    uint, /*takerGives*/ // silence warning about unused argument
    uint, /* offerGasprice*/ // silence warning about unused argument
    uint /*offerId */ // silence warning about unused argument
  ) external {
    (bool success, bytes memory retdata) = address(dex).call(reentrancer);
    if (success) {
      TestEvents.fail("should fail on reentrancy lock");
    } else {
      string memory r = string(retdata);
      TestEvents.eq(r, "dex/reentrancyLocked", "wrong revert reason");
    }
  }

  function newOffer_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(1 ether, 1 ether, 30_000, 0);
    reentrancer = abi.encodeWithSelector(
      Dex.newOffer.selector,
      1 ether,
      1 ether,
      30_000,
      0
    );
    tkr.take(ofr, 1 ether);
  }

  function cancelOffer_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(1 ether, 1 ether, 30_000, 0);
    reentrancer = abi.encodeWithSelector(
      Dex.cancelOffer.selector,
      1 ether,
      1 ether,
      30_000,
      0
    );
    tkr.take(ofr, 1 ether);
  }

  function marketOrder_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(1 ether, 1 ether, 30_000, 0);
    reentrancer = abi.encodeWithSelector(
      Dex.simpleMarketOrder.selector,
      1 ether,
      1 ether
    );
    tkr.take(ofr, 1 ether);
  }

  function internalSnipes_on_reentrancy_fails_test() public {
    uint ofr = dex.newOffer(1 ether, 1 ether, 30_000, 0);
    reentrancer = abi.encodeWithSelector(Dex.snipe.selector, 0, 1 ether);
    tkr.take(ofr, 1 ether);
  }

  function newOffer_on_closed_fails_test() public {
    dex.closeMarket();
    try dex.newOffer(1 ether, 1 ether, 0, 0)  {
      TestEvents.fail("newOffer should fail on closed market");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/closed", "wrong revert reason");
    }
  }

  function receive_on_closed_fails_test() public {
    dex.closeMarket();

    (bool success, bytes memory retdata) = address(dex).call{value: 10 ether}(
      ""
    );
    if (success) {
      TestEvents.fail("receive() should fail on closed market");
    } else {
      string memory r = string(retdata);
      TestEvents.eq(r, "dex/closed", "wrong revert reason");
    }
  }

  function marketOrder_on_closed_fails_test() public {
    dex.closeMarket();
    try tkr.marketOrder(1 ether, 1 ether)  {
      TestEvents.fail("marketOrder should fail on closed market");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/closed", "wrong revert reason");
    }
  }

  function snipe_on_closed_fails_test() public {
    dex.closeMarket();
    try tkr.take(0, 1 ether)  {
      TestEvents.fail("snipe should fail on closed market");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/closed", "wrong revert reason");
    }
  }

  function withdraw_on_closed_ok_test() public {
    dex.closeMarket();
    dex.withdraw(0.1 ether);
  }

  function cancelOffer_on_closed_ok_test() public {
    uint ofr = dex.newOffer(1 ether, 1 ether, 0, 0);
    dex.closeMarket();
    dex.cancelOffer(ofr);
  }
}
