// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

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

contract MakerOperations_Test is IMaker {
  Dex dex;
  TestMaker mkr;
  TestMaker mkr2;
  TestTaker tkr;
  TestToken base;
  TestToken quote;

  receive() external payable {}

  function a_beforeAll() public {
    base = TokenSetup.setup("A", "$A");
    quote = TokenSetup.setup("B", "$B");
    dex = DexSetup.setup(base, quote);
    mkr = MakerSetup.setup(dex, address(base), address(quote));
    mkr2 = MakerSetup.setup(dex, address(base), address(quote));
    tkr = TakerSetup.setup(dex, address(base), address(quote));

    address(mkr).transfer(10 ether);
    mkr.approveDex(base, 10 ether);
    address(mkr2).transfer(10 ether);
    mkr2.approveDex(base, 10 ether);

    address(tkr).transfer(10 ether);

    quote.mint(address(tkr), 1 ether);
    tkr.approveDex(quote, 1 ether);

    base.approve(address(dex), 10 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "MakerOperations_Test");
    Display.register(address(base), "$A");
    Display.register(address(quote), "$B");
    Display.register(address(dex), "dex");
    Display.register(address(mkr), "maker");
    Display.register(address(mkr2), "maker2");
    Display.register(address(tkr), "taker");
  }

  function provision_adds_freeWei_and_ethers_test() public {
    uint dex_bal = address(dex).balance;
    uint amt1 = 235;
    uint amt2 = 1.3 ether;

    mkr.provisionDex(amt1);

    TestEvents.eq(mkr.freeWei(), amt1, "incorrect mkr freeWei amount (1)");
    TestEvents.eq(
      address(dex).balance,
      dex_bal + amt1,
      "incorrect dex ETH balance (1)"
    );

    mkr.provisionDex(amt2);

    TestEvents.eq(
      mkr.freeWei(),
      amt1 + amt2,
      "incorrect mkr freeWei amount (2)"
    );
    TestEvents.eq(
      address(dex).balance,
      dex_bal + amt1 + amt2,
      "incorrect dex ETH balance (2)"
    );
  }

  // since we check calldata, execute must be internal
  function makerTrade(DC.SingleOrder calldata order)
    external
    override
    returns (bytes32 ret)
  {
    ret; // silence unused function parameter warning
    uint num_args = 9;
    uint selector_bytes = 4;
    uint length = selector_bytes + num_args * 32;
    TestEvents.eq(
      msg.data.length,
      length,
      "calldata length in execute is incorrect"
    );

    TestEvents.eq(order.base, address(base), "wrong base");
    TestEvents.eq(order.quote, address(quote), "wrong quote");
    TestEvents.eq(order.wants, 0.05 ether, "wrong takerWants");
    TestEvents.eq(order.gives, 0.05 ether, "wrong takerGives");
    TestEvents.eq(
      DexPack.offer_unpack_gasprice(order.offer),
      dex.config(order.base, order.quote).global.gasprice,
      "wrong gasprice"
    );
    TestEvents.eq(
      DexPack.offerDetail_unpack_gasreq(order.offerDetail),
      200_000,
      "wrong gasreq"
    );
    TestEvents.eq(order.offerId, 1, "wrong offerId");
    TestEvents.eq(
      DexPack.offer_unpack_wants(order.offer),
      0.05 ether,
      "wrong offerWants"
    );
    TestEvents.eq(
      DexPack.offer_unpack_gives(order.offer),
      0.05 ether,
      "wrong offerGives"
    );
    // test flashloan
    TestEvents.eq(
      quote.balanceOf(address(this)),
      0.05 ether,
      "wrong quote balance"
    );
  }

  function makerPosthook(
    DC.SingleOrder calldata order,
    DC.OrderResult calldata result
  ) external override {}

  function calldata_and_balance_in_makerTrade_are_correct_test() public {
    bool funded;
    (funded, ) = address(dex).call{value: 1 ether}("");
    base.mint(address(this), 1 ether);
    uint ofr =
      dex.newOffer(
        address(base),
        address(quote),
        0.05 ether,
        0.05 ether,
        200_000,
        0,
        0
      );
    require(tkr.take(ofr, 0.05 ether), "take must work or test is void");
  }

  function withdraw_removes_freeWei_and_ethers_test() public {
    uint dex_bal = address(dex).balance;
    uint amt1 = 0.86 ether;
    uint amt2 = 0.12 ether;

    mkr.provisionDex(amt1);
    bool success = mkr.withdrawDex(amt2);
    TestEvents.check(success, "mkr was not able to withdraw from dex");
    TestEvents.eq(mkr.freeWei(), amt1 - amt2, "incorrect mkr freeWei amount");
    TestEvents.eq(
      address(dex).balance,
      dex_bal + amt1 - amt2,
      "incorrect dex ETH balance"
    );
  }

  function withdraw_too_much_fails_test() public {
    uint amt1 = 6.003 ether;
    mkr.provisionDex(amt1);
    try mkr.withdrawDex(amt1 + 1) {
      TestEvents.fail("mkr cannot withdraw more than it has");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/insufficientProvision", "wrong revert reason");
    }
  }

  function newOffer_without_freeWei_fails_test() public {
    try mkr.newOffer(1 ether, 1 ether, 0, 0) {
      TestEvents.fail("mkr cannot create offer without provision");
    } catch Error(string memory r) {
      TestEvents.eq(
        r,
        "dex/insufficientProvision",
        "new offer failed for wrong reason"
      );
    }
  }

  function delete_restores_balance_test() public {
    mkr.provisionDex(1 ether);
    uint bal = mkr.freeWei();
    mkr.deleteOffer(mkr.newOffer(1 ether, 1 ether, 2300, 0));

    TestEvents.eq(mkr.freeWei(), bal, "delete has not restored balance");
  }

  function delete_offer_log_test() public {
    mkr.provisionDex(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 2300, 0);
    mkr.deleteOffer(ofr);
    TestEvents.expectFrom(address(dex));
    emit DexEvents.DeleteOffer(address(base), address(quote), ofr);
  }

  function retract_offer_log_test() public {
    mkr.provisionDex(1 ether);
    uint ofr = mkr.newOffer(0.9 ether, 1 ether, 2300, 100);
    mkr.retractOffer(ofr);
    TestEvents.expectFrom(address(dex));
    emit DexEvents.RetractOffer(address(base), address(quote), ofr);
  }

  function retract_offer_maintains_balance_test() public {
    mkr.provisionDex(1 ether);
    uint bal = mkr.freeWei();
    uint prov =
      TestUtils.getProvision(dex, address(base), address(quote), 2300);
    mkr.retractOffer(mkr.newOffer(1 ether, 1 ether, 2300, 0));
    TestEvents.eq(mkr.freeWei(), bal - prov, "unexpected maker balance");
  }

  function retract_middle_offer_leaves_a_valid_book_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(0.9 ether, 1 ether, 2300, 100);
    uint ofr =
      mkr.newOffer({
        wants: 1 ether,
        gives: 1 ether,
        gasreq: 2300,
        gasprice: 100,
        pivotId: 0
      });
    uint ofr1 = mkr.newOffer(1.1 ether, 1 ether, 2300, 100);

    mkr.retractOffer(ofr);
    (bool exists, DC.Offer memory offer, ) =
      dex.offerInfo(address(base), address(quote), ofr);
    TestEvents.check(!exists, "Offer was not removed from OB");
    TestEvents.eq(offer.prev, ofr0, "Invalid prev");
    TestEvents.eq(offer.next, ofr1, "Invalid next");
    TestEvents.eq(offer.gives, 0, "offer gives was not set to 0");
    TestEvents.eq(offer.gasprice, 100, "offer gasprice is incorrect");

    (bool exists0, DC.Offer memory offer0, ) =
      dex.offerInfo(address(base), address(quote), offer.prev);
    (bool exists1, DC.Offer memory offer1, ) =
      dex.offerInfo(address(base), address(quote), offer.next);
    TestEvents.check(exists0 && exists1, "Invalid OB");
    TestEvents.eq(offer1.prev, ofr0, "Invalid snitching for ofr1");
    TestEvents.eq(offer0.next, ofr1, "Invalid snitching for ofr0");
  }

  function retract_best_offer_leaves_a_valid_book_test() public {
    mkr.provisionDex(10 ether);
    uint ofr =
      mkr.newOffer({
        wants: 1 ether,
        gives: 1 ether,
        gasreq: 2300,
        gasprice: 100,
        pivotId: 0
      });
    uint ofr1 = mkr.newOffer(1.1 ether, 1 ether, 2300, 100);
    mkr.retractOffer(ofr);
    (bool exists, DC.Offer memory offer, ) =
      dex.offerInfo(address(base), address(quote), ofr);
    TestEvents.check(!exists, "Offer was not removed from OB");
    TestEvents.eq(offer.prev, 0, "Invalid prev");
    TestEvents.eq(offer.next, ofr1, "Invalid next");
    TestEvents.eq(offer.gives, 0, "offer gives was not set to 0");
    TestEvents.eq(offer.gasprice, 100, "offer gasprice is incorrect");

    (bool exists1, DC.Offer memory offer1, ) =
      dex.offerInfo(address(base), address(quote), offer.next);
    TestEvents.check(exists1, "Invalid OB");
    TestEvents.eq(offer1.prev, 0, "Invalid snitching for ofr1");
    DexCommon.Config memory cfg = dex.config(address(base), address(quote));
    TestEvents.eq(cfg.local.best, ofr1, "Invalid best after retract");
  }

  function retract_worst_offer_leaves_a_valid_book_test() public {
    mkr.provisionDex(10 ether);
    uint ofr =
      mkr.newOffer({
        wants: 1 ether,
        gives: 1 ether,
        gasreq: 2300,
        gasprice: 100,
        pivotId: 0
      });
    uint ofr0 = mkr.newOffer(0.9 ether, 1 ether, 2300, 100);
    mkr.retractOffer(ofr);
    (bool exists, DC.Offer memory offer, ) =
      dex.offerInfo(address(base), address(quote), ofr);
    TestEvents.check(!exists, "Offer was not removed from OB");
    TestEvents.eq(offer.prev, ofr0, "Invalid prev");
    TestEvents.eq(offer.next, 0, "Invalid next");
    TestEvents.eq(offer.gives, 0, "offer gives was not set to 0");
    TestEvents.eq(offer.gasprice, 100, "offer gasprice is incorrect");

    (bool exists0, DC.Offer memory offer0, ) =
      dex.offerInfo(address(base), address(quote), offer.prev);
    TestEvents.check(exists0, "Invalid OB");
    TestEvents.eq(offer0.next, 0, "Invalid snitching for ofr0");
    DexCommon.Config memory cfg = dex.config(address(base), address(quote));
    TestEvents.eq(cfg.local.best, ofr0, "Invalid best after retract");
  }

  function delete_wrong_offer_fails_test() public {
    mkr.provisionDex(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 2300, 0);
    try mkr2.deleteOffer(ofr) {
      TestEvents.fail("mkr2 should not be able to delete mkr's offer");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/retractOffer/unauthorized", "wrong revert reason");
    }
  }

  function retract_wrong_offer_fails_test() public {
    mkr.provisionDex(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 2300, 0);
    try mkr2.retractOffer(ofr) {
      TestEvents.fail("mkr2 should not be able to retract mkr's offer");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/retractOffer/unauthorized", "wrong revert reason");
    }
  }

  function gasreq_max_with_newOffer_ok_test() public {
    mkr.provisionDex(1 ether);
    uint gasmax = 750000;
    dex.setGasmax(gasmax);
    mkr.newOffer(1 ether, 1 ether, gasmax, 0);
  }

  function gasreq_too_high_fails_newOffer_test() public {
    uint gasmax = 12;
    dex.setGasmax(gasmax);
    try mkr.newOffer(1 ether, 1 ether, gasmax + 1, 0) {
      TestEvents.fail("gasreq above gasmax, newOffer should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/writeOffer/gasreq/tooHigh", "wrong revert reason");
    }
  }

  function min_density_with_newOffer_ok_test() public {
    mkr.provisionDex(1 ether);
    uint density = 10**7;
    dex.setGasbase(address(base), address(quote), 1);
    dex.setDensity(address(base), address(quote), density);
    mkr.newOffer(1 ether, density, 0, 0);
  }

  function low_density_fails_newOffer_test() public {
    uint density = 10**7;
    dex.setGasbase(address(base), address(quote), 1);
    dex.setDensity(address(base), address(quote), density);
    try mkr.newOffer(1 ether, density - 1, 0, 0) {
      TestEvents.fail("density too low, newOffer should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/writeOffer/density/tooLow", "wrong revert reason");
    }
  }

  function maker_gets_no_freeWei_on_partial_fill_test() public {
    mkr.provisionDex(1 ether);
    base.mint(address(mkr), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint oldBalance = dex.balanceOf(address(mkr));
    bool success = tkr.take(ofr, 0.1 ether);
    TestEvents.check(success, "take must succeed");
    TestEvents.eq(
      dex.balanceOf(address(mkr)),
      oldBalance,
      "mkr balance must not change"
    );
  }

  function maker_gets_no_freeWei_on_full_fill_test() public {
    mkr.provisionDex(1 ether);
    base.mint(address(mkr), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint oldBalance = dex.balanceOf(address(mkr));
    bool success = tkr.take(ofr, 1 ether);
    TestEvents.check(success, "take must succeed");
    TestEvents.eq(
      dex.balanceOf(address(mkr)),
      oldBalance,
      "mkr balance must not change"
    );
  }

  function insertions_are_correctly_ordered_test() public {
    mkr.provisionDex(10 ether);
    uint ofr2 = mkr.newOffer(1.1 ether, 1 ether, 100_000, 0);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.1 ether, 1 ether, 50_000, 0);
    uint ofr01 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.config(address(base), address(quote));
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    (bool exists, DexCommon.Offer memory offer, ) =
      dex.offerInfo(address(base), address(quote), ofr0);
    TestEvents.check(exists, "Oldest equivalent offer should be first");
    uint _ofr01 = offer.next;
    TestEvents.eq(_ofr01, ofr01, "Wrong 2nd offer");
    (exists, offer, ) = dex.offerInfo(address(base), address(quote), _ofr01);
    TestEvents.check(exists, "2nd offer was not correctly posted to dex");
    uint _ofr1 = offer.next;
    TestEvents.eq(_ofr1, ofr1, "Wrong 3rd offer");
    (exists, offer, ) = dex.offerInfo(address(base), address(quote), _ofr1);
    TestEvents.check(exists, "3rd offer was not correctly inserted");
    uint _ofr2 = offer.next;
    TestEvents.eq(_ofr2, ofr2, "Wrong 4th offer");
    (exists, offer, ) = dex.offerInfo(address(base), address(quote), _ofr2);
    TestEvents.check(exists, "3rd offer was not correctly inserted");
    TestEvents.eq(offer.next, 0, "Invalid OB");
  }

  // insertTest price, density (gives/gasreq) vs (gives'/gasreq'), age
  // nolongerBest
  // idemPrice
  // idemBest
  // A.BCD --> ABC.D

  function update_offer_resets_age_and_updates_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.config(address(base), address(quote));
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_000, ofr0, ofr0);
    uint best = dex.config(address(base), address(quote)).local.best;
    TestEvents.eq(ofr1, best, "Best offer should have changed");
  }

  function update_offer_price_nolonger_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.config(address(base), address(quote));
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether + 1, 1.0 ether, 100_000, ofr0, ofr0);
    uint best = dex.config(address(base), address(quote)).local.best;
    TestEvents.eq(ofr1, best, "Best offer should have changed");
  }

  function update_offer_density_nolonger_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.config(address(base), address(quote));
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_001, ofr0, ofr0);
    uint best = dex.config(address(base), address(quote)).local.best;
    TestEvents.eq(ofr1, best, "Best offer should have changed");
  }

  function update_offer_price_with_self_as_pivot_becomes_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.config(address(base), address(quote));
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether + 1, 100_000, ofr1, ofr1);
    uint best = dex.config(address(base), address(quote)).local.best;
    TestEvents.eq(ofr1, best, "Best offer should have changed");
  }

  function update_offer_density_with_self_as_pivot_becomes_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1.0 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1.0 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.config(address(base), address(quote));
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 99_999, ofr1, ofr1);
    uint best = dex.config(address(base), address(quote)).local.best;
    Display.logOfferBook(dex, address(base), address(quote), 2);
    TestEvents.eq(best, ofr1, "Best offer should have changed");
  }

  function update_offer_price_with_best_as_pivot_becomes_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.config(address(base), address(quote));
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether + 1, 100_000, ofr0, ofr1);
    uint best = dex.config(address(base), address(quote)).local.best;
    TestEvents.eq(ofr1, best, "Best offer should have changed");
  }

  function update_offer_density_with_best_as_pivot_becomes_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1.0 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1.0 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.config(address(base), address(quote));
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 99_999, ofr0, ofr1);
    uint best = dex.config(address(base), address(quote)).local.best;
    Display.logOfferBook(dex, address(base), address(quote), 2);
    TestEvents.eq(best, ofr1, "Best offer should have changed");
  }

  function update_offer_price_with_best_as_pivot_changes_prevnext_test()
    public
  {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOffer(1.1 ether, 1 ether, 100_000, 0);
    uint ofr3 = mkr.newOffer(1.2 ether, 1 ether, 100_000, 0);

    (bool exists, DexCommon.Offer memory offer, ) =
      dex.offerInfo(address(base), address(quote), ofr);
    TestEvents.check(exists, "Insertion error");
    TestEvents.eq(offer.prev, ofr0, "Wrong prev offer");
    TestEvents.eq(offer.next, ofr1, "Wrong next offer");
    mkr.updateOffer(1.1 ether, 1.0 ether, 100_000, ofr0, ofr);
    (exists, offer, ) = dex.offerInfo(address(base), address(quote), ofr);
    TestEvents.check(exists, "Update error");
    TestEvents.eq(offer.prev, ofr2, "Wrong prev offer after update");
    TestEvents.eq(offer.next, ofr3, "Wrong next offer after update");
  }

  function update_offer_price_with_self_as_pivot_changes_prevnext_test()
    public
  {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOffer(1.1 ether, 1 ether, 100_000, 0);
    uint ofr3 = mkr.newOffer(1.2 ether, 1 ether, 100_000, 0);

    (bool exists, DexCommon.Offer memory offer, ) =
      dex.offerInfo(address(base), address(quote), ofr);
    TestEvents.check(exists, "Insertion error");
    TestEvents.eq(offer.prev, ofr0, "Wrong prev offer");
    TestEvents.eq(offer.next, ofr1, "Wrong next offer");
    mkr.updateOffer(1.1 ether, 1.0 ether, 100_000, ofr, ofr);
    (exists, offer, ) = dex.offerInfo(address(base), address(quote), ofr);
    TestEvents.check(exists, "Update error");
    TestEvents.eq(offer.prev, ofr2, "Wrong prev offer after update");
    TestEvents.eq(offer.next, ofr3, "Wrong next offer after update");
  }

  function update_offer_density_with_best_as_pivot_changes_prevnext_test()
    public
  {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOffer(1.0 ether, 1 ether, 100_001, 0);
    uint ofr3 = mkr.newOffer(1.0 ether, 1 ether, 100_002, 0);

    (bool exists, DexCommon.Offer memory offer, ) =
      dex.offerInfo(address(base), address(quote), ofr);
    TestEvents.check(exists, "Insertion error");
    TestEvents.eq(offer.prev, ofr0, "Wrong prev offer");
    TestEvents.eq(offer.next, ofr1, "Wrong next offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_001, ofr0, ofr);
    (exists, offer, ) = dex.offerInfo(address(base), address(quote), ofr);
    TestEvents.check(exists, "Update error");
    TestEvents.eq(offer.prev, ofr2, "Wrong prev offer after update");
    TestEvents.eq(offer.next, ofr3, "Wrong next offer after update");
  }

  function update_offer_density_with_self_as_pivot_changes_prevnext_test()
    public
  {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOffer(1.0 ether, 1 ether, 100_001, 0);
    uint ofr3 = mkr.newOffer(1.0 ether, 1 ether, 100_002, 0);

    (bool exists, DexCommon.Offer memory offer, ) =
      dex.offerInfo(address(base), address(quote), ofr);
    TestEvents.check(exists, "Insertion error");
    TestEvents.eq(offer.prev, ofr0, "Wrong prev offer");
    TestEvents.eq(offer.next, ofr1, "Wrong next offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_001, ofr, ofr);
    (exists, offer, ) = dex.offerInfo(address(base), address(quote), ofr);
    TestEvents.check(exists, "Update error");
    TestEvents.eq(offer.prev, ofr2, "Wrong prev offer after update");
    TestEvents.eq(offer.next, ofr3, "Wrong next offer after update");
  }

  function update_offer_price_stays_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1.0 ether + 2, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.config(address(base), address(quote));
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether + 1, 1.0 ether, 100_000, ofr0, ofr0);
    uint best = dex.config(address(base), address(quote)).local.best;
    TestEvents.eq(ofr0, best, "Best offer should not have changed");
  }

  function update_offer_density_stays_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1.0 ether, 1 ether, 100_002, 0);
    DexCommon.Config memory cfg = dex.config(address(base), address(quote));
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_001, ofr0, ofr0);
    uint best = dex.config(address(base), address(quote)).local.best;
    TestEvents.eq(ofr0, best, "Best offer should not have changed");
  }
}
