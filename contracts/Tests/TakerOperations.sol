// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../Mangrove.sol";
import "../MgvCommon.sol";
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
  Mangrove mgv;
  TestMaker mkr;
  TestMaker refusemkr;
  TestMaker failmkr;

  receive() external payable {}

  function a_beforeAll() public {
    baseT = TokenSetup.setup("A", "$A");
    quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    mgv = MgvSetup.setup(baseT, quoteT);

    mkr = MakerSetup.setup(mgv, base, quote);
    refusemkr = MakerSetup.setup(mgv, base, quote, 1);
    failmkr = MakerSetup.setup(mgv, base, quote, 2);

    address(mkr).transfer(10 ether);
    address(refusemkr).transfer(10 ether);
    address(failmkr).transfer(10 ether);

    mkr.provisionMgv(10 ether);
    mkr.approveMgv(baseT, 10 ether);

    refusemkr.provisionMgv(1 ether);
    refusemkr.approveMgv(baseT, 10 ether);
    failmkr.provisionMgv(1 ether);
    failmkr.approveMgv(baseT, 10 ether);

    baseT.mint(address(mkr), 5 ether);
    baseT.mint(address(failmkr), 5 ether);
    baseT.mint(address(refusemkr), 5 ether);

    quoteT.mint(address(this), 5 ether);
    quoteT.mint(address(this), 5 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "taker");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(mgv), "mgv");

    Display.register(address(mkr), "maker");
    Display.register(address(failmkr), "reverting maker");
    Display.register(address(refusemkr), "refusing maker");
  }

  function snipe_reverts_if_taker_is_blacklisted_for_quote_test() public {
    uint mkr_provision = TestUtils.getProvision(mgv, base, quote, 50_000);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    quoteT.approve(address(mgv), 1 ether);
    quoteT.blacklists(address(this));
    try mgv.snipe(base, quote, ofr, 1 ether, 1 ether, 50_000) {
      TestEvents.fail("Snipe should fail");
    } catch Error(string memory msg) {
      TestEvents.eq(msg, "mgv/takerFailToPayMaker", "Unexpected revert reason");
    }
  }

  function snipe_reverts_if_taker_is_blacklisted_for_base_test() public {
    uint mkr_provision = TestUtils.getProvision(mgv, base, quote, 50_000);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    quoteT.approve(address(mgv), 1 ether);
    baseT.blacklists(address(this));
    try mgv.snipe(base, quote, ofr, 1 ether, 1 ether, 50_000) {
      TestEvents.fail("Snipe should fail");
    } catch Error(string memory msg) {
      TestEvents.eq(msg, "mgv/MgvFailToPayTaker", "Unexpected revert reason");
    }
  }

  function taker_reimbursed_if_maker_doesnt_pay_test() public {
    uint mkr_provision = TestUtils.getProvision(mgv, base, quote, 50_000);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = refusemkr.newOffer(1 ether, 1 ether, 50_000, 0);
    uint beforeQuote = quoteT.balanceOf(address(this));
    uint beforeWei = address(this).balance;
    (bool success, uint takerGot, uint takerGave) =
      mgv.snipe(base, quote, ofr, 1 ether, 1 ether, 100_000);
    uint penalty = address(this).balance - beforeWei;
    TestEvents.check(penalty > 0, "Taker should have been compensated");
    TestEvents.check(!success, "Snipe should fail");
    TestEvents.check(
      takerGot == takerGave && takerGave == 0,
      "Incorrect transaction information"
    );
    TestEvents.check(
      beforeQuote == quoteT.balanceOf(address(this)),
      "taker balance should not be lower if maker doesn't pay back"
    );
    TestEvents.expectFrom(address(mgv));
    MgvEvents.MakerFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerTransferFail",
      "testMaker/transferFail"
    );
    MgvEvents.Credit(address(refusemkr), mkr_provision - penalty);
  }

  function taker_reimbursed_if_maker_is_blacklisted_for_base_test() public {
    uint mkr_provision = TestUtils.getProvision(mgv, base, quote, 50_000);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    baseT.blacklists(address(mkr));
    uint beforeQuote = quoteT.balanceOf(address(this));
    uint beforeWei = address(this).balance;
    (bool success, uint takerGot, uint takerGave) =
      mgv.snipe(base, quote, ofr, 1 ether, 1 ether, 100_000);
    uint penalty = address(this).balance - beforeWei;
    TestEvents.check(penalty > 0, "Taker should have been compensated");
    TestEvents.check(!success, "Snipe should fail");
    TestEvents.check(
      takerGot == takerGave && takerGave == 0,
      "Incorrect transaction information"
    );
    TestEvents.check(
      beforeQuote == quoteT.balanceOf(address(this)),
      "taker balance should not be lower if maker doesn't pay back"
    );
    TestEvents.expectFrom(address(mgv));
    MgvEvents.MakerFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerTransferFail",
      ""
    );
    MgvEvents.Credit(address(mkr), mkr_provision - penalty);
  }

  function taker_reimbursed_if_maker_is_blacklisted_for_quote_test() public {
    uint mkr_provision = TestUtils.getProvision(mgv, base, quote, 50_000);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    quoteT.blacklists(address(mkr));
    uint beforeQuote = quoteT.balanceOf(address(this));
    uint beforeWei = address(this).balance;
    (bool success, uint takerGot, uint takerGave) =
      mgv.snipe(base, quote, ofr, 1 ether, 1 ether, 100_000);
    uint penalty = address(this).balance - beforeWei;
    TestEvents.check(penalty > 0, "Taker should have been compensated");
    TestEvents.check(!success, "Snipe should fail");
    TestEvents.check(
      takerGot == takerGave && takerGave == 0,
      "Incorrect transaction information"
    );
    TestEvents.check(
      beforeQuote == quoteT.balanceOf(address(this)),
      "taker balance should not be lower if maker doesn't pay back"
    );
    TestEvents.expectFrom(address(mgv));

    MgvEvents.MakerFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerReceiveFail",
      ""
    );
    MgvEvents.Credit(address(mkr), mkr_provision - penalty);
  }

  function taker_collects_failing_offer_test() public {
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = failmkr.newOffer(1 ether, 1 ether, 50_000, 0);
    uint beforeWei = address(this).balance;
    (bool success, uint takerGot, uint takerGave) =
      mgv.snipe(base, quote, ofr, 0 ether, 1 ether, 100_000);
    TestEvents.check(!success, "Snipe should fail");
    TestEvents.check(
      takerGot == takerGave && takerGave == 0,
      "Transaction data should be 0"
    );
    TestEvents.check(
      address(this).balance > beforeWei,
      "Taker was not compensated"
    );
  }

  function taker_reimbursed_if_maker_reverts_test() public {
    uint mkr_provision = TestUtils.getProvision(mgv, base, quote, 50_000);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = failmkr.newOffer(1 ether, 1 ether, 50_000, 0);
    uint beforeQuote = quoteT.balanceOf(address(this));
    uint beforeWei = address(this).balance;
    (bool success, uint takerGot, uint takerGave) =
      mgv.snipe(base, quote, ofr, 1 ether, 1 ether, 100_000);
    uint penalty = address(this).balance - beforeWei;
    TestEvents.check(penalty > 0, "Taker should have been compensated");
    TestEvents.check(!success, "Snipe should fail");
    TestEvents.check(
      takerGot == takerGave && takerGave == 0,
      "Incorrect transaction information"
    );
    TestEvents.check(
      beforeQuote == quoteT.balanceOf(address(this)),
      "taker balance should not be lower if maker doesn't pay back"
    );
    TestEvents.expectFrom(address(mgv));
    MgvEvents.MakerFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerRevert",
      "testMaker/revert"
    );
    MgvEvents.Credit(address(failmkr), mkr_provision - penalty);
  }

  function taker_hasnt_approved_base_succeeds_order_with_fee_test() public {
    mgv.setFee(base, quote, 3);
    uint balTaker = baseT.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    quoteT.approve(address(mgv), 1 ether);
    try mgv.snipe(base, quote, ofr, 1 ether, 1 ether, 50_000) {
      TestEvents.eq(
        baseT.balanceOf(address(this)) - balTaker,
        1 ether,
        "Incorrect delivered amount"
      );
    } catch Error(string memory r) {
      TestEvents.fail("Snipe should succeed");
    }
  }

  function taker_hasnt_approved_base_succeeds_order_wo_fee_test() public {
    uint balTaker = baseT.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    quoteT.approve(address(mgv), 1 ether);
    try mgv.snipe(base, quote, ofr, 1 ether, 1 ether, 50_000) {
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
    baseT.approve(address(mgv), 1 ether);
    try mgv.snipe(base, quote, ofr, 1 ether, 1 ether, 50_000) {
      TestEvents.fail("Order should fail when base is not mgv approved");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/takerFailToPayMaker", "wrong revert reason");
    }
  }

  function simple_snipe_test() public {
    uint ofr = mkr.newOffer(1.1 ether, 1 ether, 50_000, 0);
    baseT.approve(address(mgv), 10 ether);
    quoteT.approve(address(mgv), 10 ether);
    uint balTaker = baseT.balanceOf(address(this));
    uint balMaker = quoteT.balanceOf(address(mkr));
    try mgv.snipe(base, quote, ofr, 1 ether, 1.1 ether, 50_000) returns (
      bool success,
      uint takerGot,
      uint takerGave
    ) {
      TestEvents.check(success, "Snipe should succeed");
      TestEvents.eq(
        baseT.balanceOf(address(this)) - balTaker,
        1 ether,
        "Incorrect delivered amount (taker)"
      );
      TestEvents.eq(
        quoteT.balanceOf(address(mkr)) - balMaker,
        1.1 ether,
        "Incorrect delivered amount (maker)"
      );
      TestEvents.eq(takerGot, 1 ether, "Incorrect transaction information");
      TestEvents.eq(takerGave, 1.1 ether, "Incorrect transaction information");
      TestEvents.expectFrom(address(mgv));
      emit MgvEvents.Success(
        base,
        quote,
        ofr,
        address(this),
        1 ether,
        1.1 ether
      );
    } catch {
      TestEvents.fail("Snipe should succeed");
    }
  }

  function simple_marketOrder_test() public {
    mkr.newOffer(1.1 ether, 1 ether, 50_000, 0);
    mkr.newOffer(1.2 ether, 1 ether, 50_000, 0);

    baseT.approve(address(mgv), 10 ether);
    quoteT.approve(address(mgv), 10 ether);
    uint balTaker = baseT.balanceOf(address(this));
    uint balMaker = quoteT.balanceOf(address(mkr));

    try mgv.marketOrder(base, quote, 2 ether, 4 ether) returns (
      uint takerGot,
      uint takerGave
    ) {
      TestEvents.eq(
        takerGot,
        2 ether,
        "Incorrect declared delivered amount (taker)"
      );
      TestEvents.eq(
        takerGave,
        2.3 ether,
        "Incorrect declared delivered amount (maker)"
      );
      TestEvents.eq(
        baseT.balanceOf(address(this)) - balTaker,
        2 ether,
        "Incorrect delivered amount (taker)"
      );
      TestEvents.eq(
        quoteT.balanceOf(address(mkr)) - balMaker,
        2.3 ether,
        "Incorrect delivered amount (maker)"
      );
    } catch {
      TestEvents.fail("Market order should succeed");
    }
  }

  function taker_has_no_quote_fails_order_test() public {
    uint ofr = mkr.newOffer(100 ether, 2 ether, 50_000, 0);
    quoteT.approve(address(mgv), 100 ether);
    baseT.approve(address(mgv), 1 ether); // not necessary since no fee
    try mgv.snipe(base, quote, ofr, 2 ether, 100 ether, 100_000) {
      TestEvents.fail(
        "Taker does not have enough quote tokens, order should fail"
      );
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/takerFailToPayMaker", "wrong revert reason");
    }
  }

  function maker_has_not_enough_base_fails_order_test() public {
    uint ofr = mkr.newOffer(1 ether, 100 ether, 100_000, 0);
    // getting rid of base tokens
    //mkr.transferToken(baseT,address(this),5 ether);
    quoteT.approve(address(mgv), 0.5 ether);
    (bool success, , ) =
      mgv.snipe(base, quote, ofr, 50 ether, 0.5 ether, 100_000);
    TestEvents.check(!success, "order should fail");
    TestEvents.expectFrom(address(mgv));
    emit MgvEvents.MakerFail(
      base,
      quote,
      ofr,
      address(this),
      50 ether,
      0.5 ether,
      "mgv/makerTransferFail",
      ""
    );
  }

  function maker_revert_is_logged_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    mkr.shouldRevert(true);
    quoteT.approve(address(mgv), 1 ether);
    mgv.snipe(base, quote, ofr, 1 ether, 1 ether, 50_000);
    TestEvents.expectFrom(address(mgv));
    emit MgvEvents.MakerFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerRevert",
      "testMaker/revert"
    );
  }

  function snipe_on_higher_price_fails_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    quoteT.approve(address(mgv), 0.5 ether);
    (bool success, , ) =
      mgv.snipe(base, quote, ofr, 1 ether, 0.5 ether, 100_000);
    TestEvents.check(
      !success,
      "Order should fail when order price is higher than offer"
    );
  }

  function snipe_on_higher_gas_fails_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    quoteT.approve(address(mgv), 1 ether);
    (bool success, , ) = mgv.snipe(base, quote, ofr, 1 ether, 1 ether, 50_000);
    TestEvents.check(
      !success,
      "Order should fail when order gas is higher than offer"
    );
  }

  function detect_lowgas_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    quoteT.approve(address(mgv), 100 ether);

    bytes memory cd =
      abi.encodeWithSelector(
        Mangrove.snipe.selector,
        base,
        quote,
        ofr,
        1 ether,
        1 ether,
        100_000
      );

    (bool noRevert, bytes memory data) = address(mgv).call{gas: 130000}(cd);
    if (noRevert) {
      TestEvents.fail("take should fail due to low gas");
    } else {
      TestEvents.revertEq(
        TestUtils.getReason(data),
        "mgv/notEnoughGasForMakerTrade"
      );
    }
  }

  function snipe_on_lower_price_succeeds_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    quoteT.approve(address(mgv), 2 ether);
    uint balTaker = baseT.balanceOf(address(this));
    uint balMaker = quoteT.balanceOf(address(mkr));
    (bool success, , ) = mgv.snipe(base, quote, ofr, 1 ether, 2 ether, 100_000);
    TestEvents.check(
      success,
      "Order should succeed when order price is lower than offer"
    );
    // checking order was executed at Maker's price
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
  }

  /* Note as for jan 5 2020: by locally pushing the block gas limit to 38M, you can go up to 162 levels of recursion before hitting "revert for an unknown reason" -- I'm assuming that's the stack limit. */
  function recursion_depth_is_acceptable_test() public {
    for (uint i = 0; i < 50; i++) {
      mkr.newOffer(0.001 ether, 0.001 ether, 50_000, i);
    }
    quoteT.approve(address(mgv), 10 ether);
    // 6/1/20 : ~50k/offer with optims
    //uint g = gasleft();
    //console.log("gas used per offer: ",(g-gasleft())/50);
  }

  function partial_fill_test() public {
    quoteT.approve(address(mgv), 1 ether);
    mkr.newOffer(0.1 ether, 0.1 ether, 50_000, 0);
    mkr.newOffer(0.1 ether, 0.1 ether, 50_000, 1);
    (uint takerGot, ) = mgv.marketOrder(base, quote, 0.15 ether, 0.15 ether);
    TestEvents.eq(
      takerGot,
      0.15 ether,
      "Incorrect declared partial fill amount"
    );
    TestEvents.eq(
      baseT.balanceOf(address(this)),
      0.15 ether,
      "incorrect partial fill"
    );
  }

  // ! unreliable test, depends on gas use
  function market_order_stops_for_high_price_test() public {
    quoteT.approve(address(mgv), 1 ether);
    for (uint i = 0; i < 10; i++) {
      mkr.newOffer((i + 1) * (0.1 ether), 0.1 ether, 50_000, i);
    }
    // first two offers are at right price
    uint takerWants = 2 * (0.1 ether + 0.1 ether);
    uint takerGives = 2 * (0.1 ether + 0.2 ether);
    mgv.marketOrder{gas: 350_000}(base, quote, takerWants, takerGives);
  }

  // ! unreliable test, depends on gas use
  function market_order_stops_for_filled_mid_offer_test() public {
    quoteT.approve(address(mgv), 1 ether);
    for (uint i = 0; i < 10; i++) {
      mkr.newOffer((i + 1) * (0.1 ether), 0.1 ether, 50_000, i);
    }
    // first two offers are at right price
    uint takerWants = 0.1 ether + 0.05 ether;
    uint takerGives = 0.1 ether + 0.1 ether;
    mgv.marketOrder{gas: 350_000}(base, quote, takerWants, takerGives);
  }

  function market_order_stops_for_filled_after_offer_test() public {
    quoteT.approve(address(mgv), 1 ether);
    for (uint i = 0; i < 10; i++) {
      mkr.newOffer((i + 1) * (0.1 ether), 0.1 ether, 50_000, i);
    }
    // first two offers are at right price
    uint takerWants = 0.1 ether + 0.1 ether;
    uint takerGives = 0.1 ether + 0.2 ether;
    mgv.marketOrder{gas: 350_000}(base, quote, takerWants, takerGives);
  }

  function takerWants_wider_than_160_bits_fails_marketOrder_test() public {
    try mgv.marketOrder(base, quote, 2**160, 1) {
      TestEvents.fail("TakerWants > 160bits, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/mOrder/takerWants/160bits", "wrong revert reason");
    }
  }

  function snipe_with_0_wants_ejects_offer_test() public {
    quoteT.approve(address(mgv), 1 ether);
    uint mkrBal = baseT.balanceOf(address(mkr));
    uint ofr = mkr.newOffer(0.1 ether, 0.1 ether, 50_000, 0);
    (bool success, , ) = mgv.snipe(base, quote, ofr, 0, 1 ether, 50_000);
    TestEvents.check(success, "snipe should succeed");
    TestEvents.eq(mgv.best(base, quote), 0, "offer should be gone");
    TestEvents.eq(
      baseT.balanceOf(address(mkr)),
      mkrBal,
      "mkr balance should not change"
    );
  }

  function unsafe_gas_left_fails_order_test() public {
    mgv.setGasbase(base, quote, 1, 1);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 120_000, 0);
    try mgv.snipe{gas: 120_000}(base, quote, ofr, 1 ether, 1 ether, 120_000) {
      TestEvents.fail("unsafe gas amount, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/notEnoughGasForMakerTrade", "wrong revert reason");
    }
  }

  function marketOrder_on_empty_book_returns_test() public {
    try mgv.marketOrder(base, quote, 1 ether, 1 ether) {
      TestEvents.succeed();
    } catch Error(string memory) {
      TestEvents.fail("market order on empty book should not fail");
    }
  }

  function marketOrder_on_empty_book_does_not_leave_lock_on_test() public {
    mgv.marketOrder(base, quote, 1 ether, 1 ether);
    TestEvents.check(
      !mgv.locked(base, quote),
      "mgv should not be locked after marketOrder on empty OB"
    );
  }
}
