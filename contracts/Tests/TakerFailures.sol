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
import "./Agents/MakerDeployer.sol";
import "./Agents/TestTaker.sol";

/* The following constructs an ERC20 with a transferFrom callback method,
   and a TestTaker which throws away any funds received upon getting
   a callback.
*/
interface CallableRecipient {
  function received(
    ERC20 token,
    address sender,
    uint amount
  ) external;
}

contract BlackholeTaker is TestTaker, CallableRecipient {
  constructor(Dex _dex) TestTaker(_dex) {}

  bool enabled;

  function setEnabled(bool b) external {
    enabled = b;
  }

  // sends all received funds into a black hole
  function received(
    ERC20 token,
    address, /* sender*/ // silence warning about unused argument
    uint amount
  ) external override {
    if (enabled) {
      // ERC20 has protection against sending to 0
      address blackhole = address(0x1);
      token.transfer(blackhole, amount);
    }
  }
}

library BlackholeTakerSetup {
  function setup(Dex dex) external returns (BlackholeTaker) {
    return new BlackholeTaker(dex);
  }
}

contract TokenWithCb is TestToken {
  constructor(
    address admin,
    string memory name,
    string memory symbol
  ) TestToken(admin, name, symbol) {}

  function transferFrom(
    address sender,
    address recipient,
    uint amount
  ) public virtual override returns (bool ret) {
    ret = super.transferFrom(sender, recipient, amount);
    CallableRecipient cr = CallableRecipient(recipient);
    ERC20 that = ERC20(address(this));
    try cr.received(that, sender, amount)  {} catch {}
  }
}

library TokenWithCbSetup {
  function setup(
    address admin,
    string memory name,
    string memory symbol
  ) external returns (TokenWithCb) {
    return new TokenWithCb(admin, name, symbol);
  }
}

contract TakerFailures_Test {
  TestToken atk;
  TestToken btk;
  Dex dex;
  BlackholeTaker tkr;
  TestMaker mkr;

  receive() external payable {}

  function a_beforeAll() public {
    atk = TokenWithCbSetup.setup(address(this), "A", "$A");
    btk = TokenSetup.setup("B", "$B");
    dex = DexSetup.setup(atk, btk);
    tkr = BlackholeTakerSetup.setup(dex);
    mkr = MakerSetup.setup(dex, false);

    address(mkr).transfer(10 ether);
    address(tkr).transfer(1 ether);

    mkr.provisionDex(1 ether);

    atk.mint(address(mkr), 1 ether);
    btk.mint(address(tkr), 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "TakerFailures_Test");
    Display.register(address(atk), "$A");
    Display.register(address(btk), "$B");
    Display.register(address(dex), "dex");
    Display.register(address(mkr), "maker");
    Display.register(address(tkr), "taker");
  }

  function taker_hasnt_approved_B_fails_order_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 0, 0);
    try tkr.take(ofr, 1 ether)  {
      TestEvents.fail("Taker hasn't approved B, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/takerFailToPayMaker", "wrong revert reason");
    }
  }

  function taker_has_no_B_fails_order_test() public {
    uint ofr = mkr.newOffer(1.1 ether, 1 ether, 10_000, 0);
    tkr.approve(btk, 1.1 ether);
    try tkr.take(ofr, 1.1 ether)  {
      TestEvents.fail("Taker doesn't have enough B, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/takerFailToPayMaker", "wrong revert reason");
    }
  }

  function maker_hasnt_approved_A_fails_order_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 0, 0);
    tkr.approve(btk, 1 ether);
    bool success = tkr.take(ofr, 1 ether);
    TestEvents.check(!success, "order should fail");
  }

  function if_maker_has_no_A_fails_order_test() public {
    uint ofr = mkr.newOffer(1 ether, 10 ether, 0, 0);
    tkr.approve(btk, 1 ether);
    mkr.approve(atk, 10 ether);
    bool success = tkr.take(ofr, 1 ether);
    TestEvents.check(!success, "order should fail");
  }

  function takerWants_wider_than_160_bits_fails_marketOrder_test() public {
    try tkr.marketOrder(2**160, 0)  {
      TestEvents.fail("TakerWants > 160bits, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(
        r,
        "dex/marketOrder/takerWants/160bits",
        "wrong revert reason"
      );
    }
  }

  function unsafe_gas_left_fails_order_test() public {
    dex.setConfig(DC.ConfigKey.gasbase, 1);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    try tkr.take{gas: 40_000}(ofr, 1 ether)  {
      TestEvents.fail("unsafe gas amount, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/unsafeGasAmount", "wrong revert reason");
    }
  }

  function taker_hasnt_approved_A_fails_order_test() public {
    dex.setConfig(DC.ConfigKey.fee, 300);
    tkr.approve(btk, 1 ether);
    mkr.approve(atk, 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 10_000, 0);
    try tkr.take(ofr, 1 ether)  {
      TestEvents.fail("Taker hasn't approved for A, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/takerFailToPayDex", "wrong revert reason");
    }
  }

  function taker_has_no_A_fails_order_test() public {
    tkr.setEnabled(true);
    dex.setConfig(DC.ConfigKey.fee, 300);
    tkr.approve(btk, 1 ether);
    mkr.approve(atk, 1 ether);
    tkr.approve(atk, 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 10_000, 0);
    try tkr.take(ofr, 1 ether)  {
      TestEvents.fail("Taker doesn't have enough A, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/takerFailToPayDex", "wrong revert reason");
    }
  }

  function marketOrder_on_empty_book_fails_test() public {
    try tkr.marketOrder(1 ether, 1 ether)  {
      TestEvents.fail("market order on empty book should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/marketOrder/noSuchOffer", "wrong revert reason");
    }
  }

  function marketOrder_with_bad_offer_id_fails_test() public {
    try tkr.probeForFail(1 ether, 1 ether, 0, 43)  {
      TestEvents.fail("market order wit bad offer id should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/marketOrder/noSuchOffer", "wrong revert reason");
    }
  }

  function taking_same_offer_twice_fails_test() public {
    tkr.approve(btk, 1 ether);
    mkr.approve(atk, 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 10_000, 0);
    tkr.take(ofr, 1 ether);
    try tkr.probeForFail(0, 0, 0, ofr)  {
      TestEvents.fail("Offer should have been deleted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/marketOrder/noSuchOffer", "wrong revert reason");
    }
  }

  function small_partial_fill_can_be_retaken_test() public {
    tkr.approve(btk, 1 ether);
    mkr.approve(atk, 1 ether);
    dex.setConfig(DC.ConfigKey.density, 1);
    dex.setConfig(DC.ConfigKey.gasbase, 1);
    uint ofr = mkr.newOffer(10_002, 10_002, 10_000, 0);
    tkr.take(ofr, 1);
    tkr.probeForFail(10_001, 10_001, 0, ofr);
  }

  function big_partial_fill_cant_be_retaken_test() public {
    tkr.approve(btk, 1 ether);
    mkr.approve(atk, 1 ether);
    dex.setConfig(DC.ConfigKey.density, 1);
    dex.setConfig(DC.ConfigKey.gasbase, 1);
    uint ofr = mkr.newOffer(10_001, 10_001, 10_000, 0);
    tkr.take(ofr, 2);
    try tkr.probeForFail(10_001, 10_001, 0, ofr)  {
      TestEvents.fail("Offer should have been deleted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/marketOrder/noSuchOffer", "wrong revert reason");
    }
  }
}
