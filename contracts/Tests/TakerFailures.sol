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
  constructor(
    Dex _dex,
    address base,
    address quote
  ) TestTaker(_dex, base, quote) {}

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
      try token.transfer(blackhole, amount) {} catch {}
    }
  }
}

library BlackholeTakerSetup {
  function setup(
    Dex dex,
    address base,
    address quote
  ) external returns (BlackholeTaker) {
    return new BlackholeTaker(dex, base, quote);
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
    ERC20 that = ERC20(address(this));
    bool noRevert;
    (noRevert, ) = recipient.call(
      abi.encodeWithSelector(
        CallableRecipient.received.selector,
        that,
        msg.sender,
        amount
      )
    );
  }

  function transfer(address recipient, uint amount)
    public
    virtual
    override
    returns (bool ret)
  {
    ret = super.transfer(recipient, amount);
    ERC20 that = ERC20(address(this));
    bool noRevert;
    (noRevert, ) = recipient.call(
      abi.encodeWithSelector(
        CallableRecipient.received.selector,
        that,
        msg.sender,
        amount
      )
    );
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
  TestToken base;
  TestToken quote;
  Dex dex;
  BlackholeTaker tkr;
  TestMaker mkr;

  receive() external payable {}

  function a_beforeAll() public {
    base = TokenWithCbSetup.setup(address(this), "A", "$A");
    quote = TokenSetup.setup("B", "$B");
    dex = DexSetup.setup(base, quote);
    tkr = BlackholeTakerSetup.setup(dex, address(base), address(quote));
    mkr = MakerSetup.setup(dex, address(base), address(quote), false);

    address(mkr).transfer(10 ether);
    address(tkr).transfer(1 ether);

    mkr.provisionDex(1 ether);

    base.mint(address(mkr), 1 ether);
    quote.mint(address(tkr), 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "TakerFailures_Test");
    Display.register(address(base), "$A");
    Display.register(address(quote), "$B");
    Display.register(address(dex), "dex");
    Display.register(address(mkr), "maker");
    Display.register(address(tkr), "taker");
  }

  function taker_hasnt_approved_B_fails_order_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 0, 0);
    try tkr.take(ofr, 1 ether) {
      TestEvents.fail("Taker hasn't approved B, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/takerFailToPayMaker", "wrong revert reason");
    }
  }

  function taker_has_no_B_fails_order_test() public {
    uint ofr = mkr.newOffer(1.1 ether, 1 ether, 10_000, 0);
    tkr.approve(quote, 1.1 ether);
    try tkr.take(ofr, 1.1 ether) {
      TestEvents.fail("Taker doesn't have enough B, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/takerFailToPayMaker", "wrong revert reason");
    }
  }

  function if_maker_has_no_A_fails_order_test() public {
    uint ofr = mkr.newOffer(1 ether, 10 ether, 100_000, 0);
    tkr.approve(quote, 1 ether);
    bool success = tkr.take(ofr, 1.1 ether);
    TestEvents.check(!success, "order should fail");
  }

  function takerWants_wider_than_160_bits_fails_marketOrder_test() public {
    try tkr.marketOrder(2**160, 0) {
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
    dex.setGasbase(1);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    try tkr.take{gas: 80_000}(ofr, 1 ether) {
      TestEvents.fail("unsafe gas amount, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/unsafeGasAmount", "wrong revert reason");
    }
  }

  function taker_hasnt_approved_A_fails_order_test() public {
    dex.setFee(address(base), address(quote), 300);
    tkr.approve(quote, 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    try tkr.take(ofr, 1 ether) {
      TestEvents.fail("Taker hasn't approved for A, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/takerFailToPayDex", "wrong revert reason");
    }
  }

  /* This test uses an ERC20 with callback and an evil taker to take out `base` received as soon as they come in. It does not make sense with a non-inverted Dex and a flashloan system based on checking balanceOf, because ERC20+callback+evilTaker means there is no way for the maker to defend against a bad taker. A version of this test could be restored in the inverted dex case, because a variant of evil maker could remove base tokens *during* its `execute` call. But with a normal Dex, we're essentially testing the ERC20 which makes no sense. */
  //function taker_has_no_A_fails_order_test() public {
  //tkr.setEnabled(true);
  //dex.setFee(address(base), address(quote), 300);
  //tkr.approve(quote, 1 ether);
  //tkr.approve(base, 1 ether);
  //uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
  //try tkr.take(ofr, 1 ether) {
  //TestEvents.fail("Taker doesn't have enough A, order should fail");
  //} catch Error(string memory r) {
  //TestEvents.eq(r, "dex/takerFailToPayDex", "wrong revert reason");
  //}
  //}

  function marketOrder_on_empty_book_fails_test() public {
    try tkr.marketOrder(1 ether, 1 ether) {
      TestEvents.fail("market order on empty book should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/marketOrder/noSuchOffer", "wrong revert reason");
    }
  }

  function marketOrder_with_bad_offer_id_fails_test() public {
    try tkr.marketOrderWithFail(1 ether, 1 ether, 0, 43) {
      TestEvents.fail("market order wit bad offer id should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/marketOrder/noSuchOffer", "wrong revert reason");
    }
  }

  function taking_same_offer_twice_fails_test() public {
    tkr.approve(quote, 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    tkr.take(ofr, 1 ether);
    try tkr.marketOrderWithFail(0, 0, 0, ofr) {
      TestEvents.fail("Offer should have been deleted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/marketOrder/noSuchOffer", "wrong revert reason");
    }
  }

  function small_partial_fill_can_be_retaken_test() public {
    tkr.approve(quote, 1 ether);
    dex.setDensity(address(base), address(quote), 1);
    dex.setGasbase(1);
    uint ofr = mkr.newOffer(100_002, 100_002, 100_000, 0);
    tkr.take(ofr, 1);
    tkr.marketOrderWithFail(100_001, 100_001, 0, ofr);
  }

  function big_partial_fill_cant_be_retaken_test() public {
    tkr.approve(quote, 1 ether);
    dex.setDensity(address(base), address(quote), 1);
    dex.setGasbase(1);
    uint ofr = mkr.newOffer(100_001, 100_001, 100_000, 0);
    tkr.take(ofr, 2);
    try tkr.marketOrderWithFail(100_001, 100_001, 0, ofr) {
      TestEvents.fail("Offer should have been deleted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/marketOrder/noSuchOffer", "wrong revert reason");
    }
  }
}
