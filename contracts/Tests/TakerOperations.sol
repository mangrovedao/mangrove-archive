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
contract TakerOperations_Test {
  TestToken baseT;
  TestToken quoteT;
  address base;
  address quote;
  Dex dex;
  TestMaker mkr;

  receive() external payable {}

  function a_beforeAll() public {
    baseT = TokenSetup.setup("A", "$A");
    quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    dex = DexSetup.setup(baseT, quoteT);
    mkr = MakerSetup.setup(dex, base, quote);

    address(mkr).transfer(10 ether);
    mkr.provisionDex(1 ether);

    baseT.mint(address(mkr), 5 ether);
    quoteT.mint(address(this), 5 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "taker");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(dex), "dex");
    Display.register(address(mkr), "maker");
  }

  function taker_hasnt_approved_base_fails_order_with_fee_test() public {
    dex.setFee(base, quote, 3);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    quoteT.approve(address(dex), 1 ether);
    try dex.snipe(base, quote, ofr, 1 ether, 1 ether, 50_000) {
      TestEvents.fail("Order should fail when base is not dex approved");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/takerFailToPayDex", "wrong revert reason");
    }
  }

  function taker_hasnt_approved_base_succeeds_order_wo_fee_test() public {
    uint balTaker = baseT.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    quoteT.approve(address(dex), 1 ether);
    try dex.snipe(base, quote, ofr, 1 ether, 1 ether, 50_000) {
      TestEvents.eq(
        baseT.balanceOf(address(this)) - balTaker,
        1 ether,
        "Incorrect delivered amount"
      );
    } catch {
      TestEvents.fail("Snipe should succeed");
    }
  }

  function taker_hasnt_approved_quote_fails_order_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    baseT.approve(address(dex), 1 ether);
    try dex.snipe(base, quote, ofr, 1 ether, 1 ether, 50_000) {
      TestEvents.fail("Order should fail when base is not dex approved");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/takerFailToPayMaker", "wrong revert reason");
    }
  }

  function simple_snipe_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    baseT.approve(address(dex), 1 ether);
    quoteT.approve(address(dex), 1 ether);
    uint balTaker = baseT.balanceOf(address(this));
    uint balMaker = quoteT.balanceOf(address(mkr));
    try dex.snipe(base, quote, ofr, 1 ether, 1 ether, 50_000) {
      TestEvents.eq(
        baseT.balanceOf(address(this)) - balTaker,
        1 ether,
        "Incorrect delivered amount (taker)"
      );
      TestEvents.eq(
        quoteT.balanceOf(address(mkr)) - balMaker,
        1 ether,
        "Incorrect delivered amount (maker)"
      );
    } catch {
      TestEvents.fail("Snipe should succeed");
    }
  }

  function simple_marketOrder_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    baseT.approve(address(dex), 1 ether);
    quoteT.approve(address(dex), 1 ether);
    uint balTaker = baseT.balanceOf(address(this));
    uint balMaker = quoteT.balanceOf(address(mkr));
    try dex.simpleMarketOrder(base, quote, 1 ether, 1 ether) {
      TestEvents.eq(
        baseT.balanceOf(address(this)) - balTaker,
        1 ether,
        "Incorrect delivered amount (taker)"
      );
      TestEvents.eq(
        quoteT.balanceOf(address(mkr)) - balMaker,
        1 ether,
        "Incorrect delivered amount (maker)"
      );
    } catch {
      TestEvents.fail("Market order should succeed");
    }
  }

  function taker_has_no_quote_fails_order_test() public {
    uint ofr = mkr.newOffer(100 ether, 2 ether, 50_000, 0);
    quoteT.approve(address(dex), 100 ether);
    baseT.approve(address(dex), 1 ether); // not necessary since no fee
    try dex.snipe(base, quote, ofr, 2 ether, 100 ether, 100_000) {
      TestEvents.fail(
        "Taker does not have enough quote tokens, order should fail"
      );
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/takerFailToPayMaker", "wrong revert reason");
    }
  }

  function maker_has_no_base_fails_order_test() public {
    uint ofr = mkr.newOffer(1 ether, 100 ether, 100_000, 0);
    quoteT.approve(address(dex), 0.5 ether);
    bool success = dex.snipe(base, quote, ofr, 50 ether, 0.5 ether, 100_000);
    TestEvents.check(!success, "order should fail");
    TestEvents.expectFrom(address(dex));
    emit DexEvents.MakerFail(ofr, 50 ether, 0.5 ether, false, 2);
  }

  function special_gas_amount_can_swapError_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    quoteT.approve(address(dex), 100 ether);

    bytes memory cd =
      abi.encodeWithSelector(
        Dex.snipe.selector,
        base,
        quote,
        ofr,
        1 ether,
        1 ether,
        100_000
      );
    (bool noRevert, bytes memory data) = address(dex).call{gas: 200000}(cd);
    if (noRevert) {
      TestEvents.fail("take should fail due to swapError");
    } else {
      TestEvents.revertEq(TestUtils.getReason(data), "dex/swapError");
    }
  }

  //
  // function unsafe_gas_left_fails_order_test() public {
  //   dex.setGasbase(1);
  //   tkr.approve(quote, 1 ether);
  //   uint ofr = mkr.newOffer(1 ether, 1 ether, 120_000, 0);
  //   try tkr.take{gas: 120_000}(ofr, 1 ether) {
  //     TestEvents.fail("unsafe gas amount, order should fail");
  //   } catch Error(string memory r) {
  //     TestEvents.eq(r, "dex/unsafeGasAmount", "wrong revert reason");
  //   }
  // }
  //
  // function taker_hasnt_approved_A_fails_order_test() public {
  //   dex.setFee(address(base), address(quote), 300);
  //   tkr.approve(quote, 1 ether);
  //   uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
  //   try tkr.take(ofr, 1 ether) {
  //     TestEvents.fail("Taker hasn't approved for A, order should fail");
  //   } catch Error(string memory r) {
  //     TestEvents.eq(r, "dex/takerFailToPayDex", "wrong revert reason");
  //   }
  // }
  //
  // /* This test uses an ERC20 with callback and an evil taker to take out `base` received as soon as they come in. It does not make sense with a non-inverted Dex and a flashloan system based on checking balanceOf, because ERC20+callback+evilTaker means there is no way for the maker to defend against a bad taker. A version of this test could be restored in the inverted dex case, because a variant of evil maker could remove base tokens *during* its `execute` call. But with a normal Dex, we're essentially testing the ERC20 which makes no sense. */
  // //function taker_has_no_A_fails_order_test() public {
  // //tkr.setEnabled(true);
  // //dex.setFee(address(base), address(quote), 300);
  // //tkr.approve(quote, 1 ether);
  // //tkr.approve(base, 1 ether);
  // //uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
  // //try tkr.take(ofr, 1 ether) {
  // //TestEvents.fail("Taker doesn't have enough A, order should fail");
  // //} catch Error(string memory r) {
  // //TestEvents.eq(r, "dex/takerFailToPayDex", "wrong revert reason");
  // //}
  // //}
  //
  // function marketOrder_on_empty_book_fails_test() public {
  //   try tkr.marketOrder(1 ether, 1 ether) {
  //     TestEvents.fail("market order on empty book should fail");
  //   } catch Error(string memory r) {
  //     TestEvents.eq(r, "dex/marketOrder/noSuchOffer", "wrong revert reason");
  //   }
  // }
  //
  // function marketOrder_with_bad_offer_id_fails_test() public {
  //   try tkr.marketOrderWithFail(1 ether, 1 ether, 0, 43) {
  //     TestEvents.fail("market order wit bad offer id should fail");
  //   } catch Error(string memory r) {
  //     TestEvents.eq(r, "dex/marketOrder/noSuchOffer", "wrong revert reason");
  //   }
  // }
  //
  // function taking_same_offer_twice_fails_test() public {
  //   tkr.approve(quote, 1 ether);
  //   uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
  //   tkr.take(ofr, 1 ether);
  //   try tkr.marketOrderWithFail(0, 0, 0, ofr) {
  //     TestEvents.fail("Offer should have been deleted");
  //   } catch Error(string memory r) {
  //     TestEvents.eq(r, "dex/marketOrder/noSuchOffer", "wrong revert reason");
  //   }
  // }
  //
  // function small_partial_fill_can_be_retaken_test() public {
  //   tkr.approve(quote, 1 ether);
  //   dex.setDensity(address(base), address(quote), 1);
  //   dex.setGasbase(1);
  //   uint ofr = mkr.newOffer(100_002, 100_002, 100_000, 0);
  //   tkr.take(ofr, 1);
  //   tkr.marketOrderWithFail(100_001, 100_001, 0, ofr);
  // }
  //
  // function big_partial_fill_cant_be_retaken_test() public {
  //   tkr.approve(quote, 1 ether);
  //   dex.setDensity(address(base), address(quote), 1);
  //   dex.setGasbase(1);
  //   uint ofr = mkr.newOffer(100_001, 100_001, 100_000, 0);
  //   tkr.take(ofr, 2);
  //   try tkr.marketOrderWithFail(100_001, 100_001, 0, ofr) {
  //     TestEvents.fail("Offer should have been deleted");
  //   } catch Error(string memory r) {
  //     TestEvents.eq(r, "dex/marketOrder/noSuchOffer", "wrong revert reason");
  //   }
  // }
}