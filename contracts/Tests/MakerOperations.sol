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
  address _base;
  address _quote;

  receive() external payable {}

  function a_beforeAll() public {
    base = TokenSetup.setup("A", "$A");
    _base = address(base);
    quote = TokenSetup.setup("B", "$B");
    _quote = address(quote);

    dex = DexSetup.setup(base, quote);
    mkr = MakerSetup.setup(dex, _base, _quote);
    mkr2 = MakerSetup.setup(dex, _base, _quote);
    tkr = TakerSetup.setup(dex, _base, _quote);

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
    Display.register(_base, "$A");
    Display.register(_quote, "$B");
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

    TestEvents.eq(order.base, _base, "wrong base");
    TestEvents.eq(order.quote, _quote, "wrong quote");
    TestEvents.eq(order.wants, 0.05 ether, "wrong takerWants");
    TestEvents.eq(order.gives, 0.05 ether, "wrong takerGives");
    TestEvents.eq(
      DexPack.offer_unpack_gasprice(order.offer),
      dex.getConfig(order.base, order.quote).global.gasprice,
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
      dex.newOffer(_base, _quote, 0.05 ether, 0.05 ether, 200_000, 0, 0);
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
    mkr.retractOfferWithDeprovision(mkr.newOffer(1 ether, 1 ether, 2300, 0));

    TestEvents.eq(mkr.freeWei(), bal, "delete has not restored balance");
  }

  function delete_offer_log_test() public {
    mkr.provisionDex(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 2300, 0);
    mkr.retractOfferWithDeprovision(ofr);
    TestEvents.expectFrom(address(dex));
    emit DexEvents.RetractOffer(_base, _quote, ofr);
  }

  function retract_offer_log_test() public {
    mkr.provisionDex(1 ether);
    uint ofr = mkr.newOffer(0.9 ether, 1 ether, 2300, 100);
    mkr.retractOffer(ofr);
    TestEvents.expectFrom(address(dex));
    emit DexEvents.RetractOffer(_base, _quote, ofr);
  }

  function retract_offer_maintains_balance_test() public {
    mkr.provisionDex(1 ether);
    uint bal = mkr.freeWei();
    uint prov = TestUtils.getProvision(dex, _base, _quote, 2300);
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
    TestEvents.check(
      !dex.isLive(dex.offers(_base, _quote, ofr)),
      "Offer was not removed from OB"
    );
    (DC.Offer memory offer, ) = dex.offerInfo(_base, _quote, ofr);
    TestEvents.eq(offer.prev, ofr0, "Invalid prev");
    TestEvents.eq(offer.next, ofr1, "Invalid next");
    TestEvents.eq(offer.gives, 0, "offer gives was not set to 0");
    TestEvents.eq(offer.gasprice, 100, "offer gasprice is incorrect");

    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, offer.prev)),
      "Invalid OB"
    );
    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, offer.next)),
      "Invalid OB"
    );
    (DC.Offer memory offer0, ) = dex.offerInfo(_base, _quote, offer.prev);
    (DC.Offer memory offer1, ) = dex.offerInfo(_base, _quote, offer.next);
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
    TestEvents.check(
      !dex.isLive(dex.offers(_base, _quote, ofr)),
      "Offer was not removed from OB"
    );
    (DC.Offer memory offer, ) = dex.offerInfo(_base, _quote, ofr);
    TestEvents.eq(offer.prev, 0, "Invalid prev");
    TestEvents.eq(offer.next, ofr1, "Invalid next");
    TestEvents.eq(offer.gives, 0, "offer gives was not set to 0");
    TestEvents.eq(offer.gasprice, 100, "offer gasprice is incorrect");

    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, offer.next)),
      "Invalid OB"
    );
    (DC.Offer memory offer1, ) = dex.offerInfo(_base, _quote, offer.next);
    TestEvents.eq(offer1.prev, 0, "Invalid snitching for ofr1");
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
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
    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, ofr)),
      "Offer was not removed from OB"
    );
    mkr.retractOffer(ofr);
    (DC.Offer memory offer, ) = dex.offerInfo(_base, _quote, ofr);
    TestEvents.eq(offer.prev, ofr0, "Invalid prev");
    TestEvents.eq(offer.next, 0, "Invalid next");
    TestEvents.eq(offer.gives, 0, "offer gives was not set to 0");
    TestEvents.eq(offer.gasprice, 100, "offer gasprice is incorrect");

    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, offer.prev)),
      "Invalid OB"
    );
    (DC.Offer memory offer0, ) = dex.offerInfo(_base, _quote, offer.prev);
    TestEvents.eq(offer0.next, 0, "Invalid snitching for ofr0");
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    TestEvents.eq(cfg.local.best, ofr0, "Invalid best after retract");
  }

  function delete_wrong_offer_fails_test() public {
    mkr.provisionDex(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 2300, 0);
    try mkr2.retractOfferWithDeprovision(ofr) {
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
    dex.setGasbase(_base, _quote, 0, 1);
    dex.setDensity(_base, _quote, density);
    mkr.newOffer(1 ether, density, 0, 0);
  }

  function low_density_fails_newOffer_test() public {
    uint density = 10**7;
    dex.setGasbase(_base, _quote, 0, 1);
    dex.setDensity(_base, _quote, density);
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
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, ofr0)),
      "Oldest equivalent offer should be first"
    );
    (DexCommon.Offer memory offer, ) = dex.offerInfo(_base, _quote, ofr0);
    uint _ofr01 = offer.next;
    TestEvents.eq(_ofr01, ofr01, "Wrong 2nd offer");
    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, _ofr01)),
      "Oldest equivalent offer should be first"
    );
    (offer, ) = dex.offerInfo(_base, _quote, _ofr01);
    uint _ofr1 = offer.next;
    TestEvents.eq(_ofr1, ofr1, "Wrong 3rd offer");
    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, _ofr1)),
      "Oldest equivalent offer should be first"
    );
    (offer, ) = dex.offerInfo(_base, _quote, _ofr1);
    uint _ofr2 = offer.next;
    TestEvents.eq(_ofr2, ofr2, "Wrong 4th offer");
    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, _ofr2)),
      "Oldest equivalent offer should be first"
    );
    (offer, ) = dex.offerInfo(_base, _quote, _ofr2);
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
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_000, ofr0, ofr0);
    uint best = dex.getConfig(_base, _quote).local.best;
    TestEvents.eq(ofr1, best, "Best offer should have changed");
  }

  function update_offer_price_nolonger_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether + 1, 1.0 ether, 100_000, ofr0, ofr0);
    uint best = dex.getConfig(_base, _quote).local.best;
    TestEvents.eq(ofr1, best, "Best offer should have changed");
  }

  function update_offer_density_nolonger_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_001, ofr0, ofr0);
    uint best = dex.getConfig(_base, _quote).local.best;
    TestEvents.eq(ofr1, best, "Best offer should have changed");
  }

  function update_offer_price_with_self_as_pivot_becomes_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether + 1, 100_000, ofr1, ofr1);
    uint best = dex.getConfig(_base, _quote).local.best;
    TestEvents.eq(ofr1, best, "Best offer should have changed");
  }

  function update_offer_density_with_self_as_pivot_becomes_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1.0 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1.0 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 99_999, ofr1, ofr1);
    uint best = dex.getConfig(_base, _quote).local.best;
    Display.logOfferBook(dex, _base, _quote, 2);
    TestEvents.eq(best, ofr1, "Best offer should have changed");
  }

  function update_offer_price_with_best_as_pivot_becomes_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether + 1, 100_000, ofr0, ofr1);
    uint best = dex.getConfig(_base, _quote).local.best;
    TestEvents.eq(ofr1, best, "Best offer should have changed");
  }

  function update_offer_density_with_best_as_pivot_becomes_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1.0 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1.0 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 99_999, ofr0, ofr1);
    uint best = dex.getConfig(_base, _quote).local.best;
    Display.logOfferBook(dex, _base, _quote, 2);
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

    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, ofr)),
      "Insertion error"
    );
    (DexCommon.Offer memory offer, ) = dex.offerInfo(_base, _quote, ofr);
    TestEvents.eq(offer.prev, ofr0, "Wrong prev offer");
    TestEvents.eq(offer.next, ofr1, "Wrong next offer");
    mkr.updateOffer(1.1 ether, 1.0 ether, 100_000, ofr0, ofr);
    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, ofr)),
      "Insertion error"
    );
    (offer, ) = dex.offerInfo(_base, _quote, ofr);
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

    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, ofr)),
      "Insertion error"
    );
    (DexCommon.Offer memory offer, ) = dex.offerInfo(_base, _quote, ofr);
    TestEvents.eq(offer.prev, ofr0, "Wrong prev offer");
    TestEvents.eq(offer.next, ofr1, "Wrong next offer");
    mkr.updateOffer(1.1 ether, 1.0 ether, 100_000, ofr, ofr);
    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, ofr)),
      "Insertion error"
    );
    (offer, ) = dex.offerInfo(_base, _quote, ofr);
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

    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, ofr)),
      "Insertion error"
    );
    (DexCommon.Offer memory offer, ) = dex.offerInfo(_base, _quote, ofr);
    TestEvents.eq(offer.prev, ofr0, "Wrong prev offer");
    TestEvents.eq(offer.next, ofr1, "Wrong next offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_001, ofr0, ofr);
    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, ofr)),
      "Update error"
    );
    (offer, ) = dex.offerInfo(_base, _quote, ofr);
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

    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, ofr)),
      "Insertion error"
    );
    (DexCommon.Offer memory offer, ) = dex.offerInfo(_base, _quote, ofr);
    TestEvents.eq(offer.prev, ofr0, "Wrong prev offer");
    TestEvents.eq(offer.next, ofr1, "Wrong next offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_001, ofr, ofr);
    TestEvents.check(
      dex.isLive(dex.offers(_base, _quote, ofr)),
      "Insertion error"
    );
    (offer, ) = dex.offerInfo(_base, _quote, ofr);
    TestEvents.eq(offer.prev, ofr2, "Wrong prev offer after update");
    TestEvents.eq(offer.next, ofr3, "Wrong next offer after update");
  }

  function update_offer_after_higher_gasprice_change_fails_test() public {
    uint provision = TestUtils.getProvision(dex, _base, _quote, 100_000);
    mkr.provisionDex(provision);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    dex.setGasprice(cfg.global.gasprice + 1); //gasprice goes up
    try mkr.updateOffer(1.0 ether + 2, 1.0 ether, 100_000, ofr0, ofr0) {
      TestEvents.fail("Update offer should have failed");
    } catch Error(string memory r) {
      TestEvents.eq(r, "dex/insufficientProvision", "wrong revert reason");
    }
  }

  function update_offer_after_higher_gasprice_change_succeeds_when_over_provisioned_test()
    public
  {
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    uint provision =
      TestUtils.getProvision(
        dex,
        _base,
        _quote,
        100_000,
        cfg.global.gasprice + 1
      );
    mkr.provisionDex(provision);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    dex.setGasprice(cfg.global.gasprice + 1); //gasprice goes up
    try mkr.updateOffer(1.0 ether + 2, 1.0 ether, 100_000, ofr0, ofr0) {
      TestEvents.expectFrom(address(dex));
      emit DexEvents.WriteOffer(
        _base,
        _quote,
        address(mkr),
        DexPack.writeOffer_pack(
          1.0 ether + 2,
          1.0 ether,
          cfg.global.gasprice + 1,
          100_000,
          ofr0
        )
      );
    } catch {
      TestEvents.fail("Update offer should have succeeded");
    }
  }

  function update_offer_after_lower_gasprice_change_succeeds_test() public {
    uint provision = TestUtils.getProvision(dex, _base, _quote, 100_000);
    mkr.provisionDex(provision);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    dex.setGasprice(cfg.global.gasprice - 1); //gasprice goes down
    uint _provision = TestUtils.getProvision(dex, _base, _quote, 100_000);
    try mkr.updateOffer(1.0 ether + 2, 1.0 ether, 100_000, ofr0, ofr0) {
      TestEvents.eq(
        dex.balanceOf(address(mkr)),
        provision - _provision,
        "Maker balance is incorrect"
      );
      TestEvents.expectFrom(address(dex));
      emit DexEvents.Credit(address(mkr), provision - _provision);
    } catch {
      TestEvents.fail("Update offer should have succeeded");
    }
  }

  function update_offer_next_to_itself_does_not_break_ob_test() public {
    mkr.provisionDex(1 ether);
    uint left = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint right = mkr.newOffer(1 ether + 3, 1 ether, 100_000, 0);
    uint center = mkr.newOffer(1 ether + 1, 1 ether, 100_000, 0);
    mkr.updateOffer(1 ether + 2, 1 ether, 100_000, center, center);
    (DexCommon.Offer memory ofr, ) = dex.offerInfo(_base, _quote, center);
    TestEvents.eq(ofr.prev, left, "ofr.prev should be unchanged");
    TestEvents.eq(ofr.next, right, "ofr.next should be unchanged");
  }

  function testOBBest(uint id) internal {
    (DexCommon.Offer memory ofr, ) = dex.offerInfo(_base, _quote, id);
    TestEvents.eq(dex.best(_base, _quote), id, "testOBBest: not best");
    TestEvents.eq(ofr.prev, 0, "testOBBest: prev not 0");
  }

  function testOBWorst(uint id) internal {
    (DexCommon.Offer memory ofr, ) = dex.offerInfo(_base, _quote, id);
    TestEvents.eq(ofr.next, 0, "testOBWorst fail");
  }

  function testOBLink(uint left, uint right) internal {
    (DexCommon.Offer memory ofr, ) = dex.offerInfo(_base, _quote, left);
    TestEvents.eq(ofr.next, right, "testOBLink: wrong ofr.next");
    (ofr, ) = dex.offerInfo(_base, _quote, right);
    TestEvents.eq(ofr.prev, left, "testOBLink: wrong ofr.prev");
  }

  function testOBOrder(uint[1] memory ids) internal {
    testOBBest(ids[0]);
    testOBWorst(ids[0]);
  }

  function testOBOrder(uint[2] memory ids) internal {
    testOBBest(ids[0]);
    testOBLink(ids[0], ids[1]);
    testOBWorst(ids[1]);
  }

  function testOBOrder(uint[3] memory ids) internal {
    testOBBest(ids[0]);
    testOBLink(ids[0], ids[1]);
    testOBLink(ids[1], ids[2]);
    testOBWorst(ids[2]);
  }

  function complex_offer_update_left_1_1_test() public {
    mkr.provisionDex(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    mkr.updateOffer(x + 1, x, g, 0, two);

    testOBOrder([one, two]);
  }

  function complex_offer_update_right_1_test() public {
    mkr.provisionDex(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    mkr.updateOffer(x + 1, x, g, two, two);

    testOBOrder([one, two]);
  }

  function complex_offer_update_left_1_2_test() public {
    mkr.provisionDex(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    mkr.updateOffer(x + 5, x, g, 0, two);

    testOBOrder([one, two]);
  }

  function complex_offer_update_right_1_2_test() public {
    mkr.provisionDex(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    mkr.updateOffer(x + 5, x, g, two, two);

    testOBOrder([one, two]);
  }

  function complex_offer_update_left_2_test() public {
    mkr.provisionDex(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    uint three = mkr.newOffer(x + 5, x, g, 0);
    mkr.updateOffer(x + 1, x, g, 0, three);

    testOBOrder([one, three, two]);
  }

  function complex_offer_update_right_2_test() public {
    mkr.provisionDex(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    uint three = mkr.newOffer(x + 5, x, g, 0);
    mkr.updateOffer(x + 4, x, g, three, one);

    testOBOrder([two, one, three]);
  }

  function complex_offer_update_left_3_test() public {
    mkr.provisionDex(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    mkr.retractOffer(two);
    mkr.updateOffer(x + 3, x, g, 0, two);

    testOBOrder([one, two]);
  }

  function complex_offer_update_right_3_test() public {
    mkr.provisionDex(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    mkr.retractOffer(one);
    mkr.updateOffer(x, x, g, 0, one);

    testOBOrder([one, two]);
  }

  function update_offer_prev_to_itself_does_not_break_ob_test() public {
    mkr.provisionDex(1 ether);
    uint left = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint right = mkr.newOffer(1 ether + 3, 1 ether, 100_000, 0);
    uint center = mkr.newOffer(1 ether + 2, 1 ether, 100_000, 0);
    mkr.updateOffer(1 ether + 1, 1 ether, 100_000, center, center);
    (DexCommon.Offer memory ofr, ) = dex.offerInfo(_base, _quote, center);
    TestEvents.eq(ofr.prev, left, "ofr.prev should be unchanged");
    TestEvents.eq(ofr.next, right, "ofr.next should be unchanged");
  }

  function update_offer_price_stays_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1.0 ether + 2, 1 ether, 100_000, 0);
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether + 1, 1.0 ether, 100_000, ofr0, ofr0);
    uint best = dex.getConfig(_base, _quote).local.best;
    TestEvents.eq(ofr0, best, "Best offer should not have changed");
  }

  function update_offer_density_stays_best_test() public {
    mkr.provisionDex(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1.0 ether, 1 ether, 100_002, 0);
    DexCommon.Config memory cfg = dex.getConfig(_base, _quote);
    TestEvents.eq(ofr0, cfg.local.best, "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_001, ofr0, ofr0);
    uint best = dex.getConfig(_base, _quote).local.best;
    TestEvents.eq(ofr0, best, "Best offer should not have changed");
  }

  function gasbase_is_deducted_1_test() public {
    uint overhead_gasbase = 100_000;
    uint offer_gasbase = 20_000;
    mkr.provisionDex(1 ether);
    dex.setGasbase(_base, _quote, overhead_gasbase, offer_gasbase);
    dex.setGasprice(1);
    dex.setDensity(_base, _quote, 0);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 0, 0);
    tkr.take(ofr, 0.1 ether);
    TestEvents.eq(
      dex.balanceOf(address(mkr)),
      1 ether - (overhead_gasbase + offer_gasbase) * 10**9,
      "Wrong gasbase deducted"
    );
  }

  function gasbase_is_deducted_2_test() public {
    uint overhead_gasbase = 100_000;
    uint offer_gasbase = 20_000;
    mkr.provisionDex(1 ether);
    dex.setGasbase(_base, _quote, overhead_gasbase, offer_gasbase);
    dex.setGasprice(1);
    dex.setDensity(_base, _quote, 0);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 0, 0);
    tkr.take(ofr, 0.1 ether);
    TestEvents.eq(
      dex.balanceOf(address(mkr)),
      1 ether - (overhead_gasbase + offer_gasbase) * 10**9,
      "Wrong gasbase deducted"
    );
  }

  // test gasbase deduction and test that gasbase changes are tracked
  function gasbase_with_change_is_deducted_multi_1_test() public {
    uint overhead_gasbase = 100_000;
    uint offer_gasbase = 20_000;
    mkr.provisionDex(1 ether);
    mkr2.provisionDex(1 ether);
    dex.setGasbase(_base, _quote, overhead_gasbase, offer_gasbase);
    dex.setGasprice(1);
    dex.setDensity(_base, _quote, 0);
    mkr2.newOffer(1 ether, 1 ether, 0, 0);
    mkr.newOffer(1 ether, 1 ether, 0, 0);
    overhead_gasbase = 90_000;
    offer_gasbase = 10_000;
    dex.setGasbase(_base, _quote, overhead_gasbase, offer_gasbase);
    tkr.marketOrder(0.1 ether, 0.1 ether);
    TestEvents.eq(
      dex.balanceOf(address(mkr)),
      1 ether - (overhead_gasbase / 2 + offer_gasbase) * 10**9,
      "Wrong gasbase deducted"
    );
  }

  // test gasbase deduction and test that gasbase changes are tracked
  function gasbase_is_deducted_multi_2_test() public {
    uint overhead_gasbase = 100_000;
    uint offer_gasbase = 20_000;
    mkr.provisionDex(1 ether);
    mkr2.provisionDex(1 ether);
    dex.setGasbase(_base, _quote, overhead_gasbase, offer_gasbase);
    dex.setGasprice(1);
    dex.setDensity(_base, _quote, 0);
    mkr2.newOffer(1 ether, 1 ether, 0, 0);
    mkr2.newOffer(1 ether, 1 ether, 0, 0);
    mkr.newOffer(1 ether, 1 ether, 0, 0);
    overhead_gasbase = 90_000;
    offer_gasbase = 10_000;
    dex.setGasbase(_base, _quote, overhead_gasbase, offer_gasbase);
    tkr.marketOrder(0.1 ether, 0.1 ether);
    TestEvents.eq(
      dex.balanceOf(address(mkr)),
      1 ether - (overhead_gasbase / 3 + offer_gasbase) * 10**9,
      "Wrong gasbase deducted"
    );
  }

  function gasbase_is_deducted_multi_3_test() public {
    uint overhead_gasbase = 30_000;
    uint offer_gasbase = 20_000;
    mkr.provisionDex(1 ether);
    mkr2.provisionDex(1 ether);
    dex.setGasbase(_base, _quote, overhead_gasbase, offer_gasbase);
    dex.setGasprice(1);
    dex.setDensity(_base, _quote, 0);
    mkr2.newOffer(1 ether, 1 ether, 0, 0);
    mkr.newOffer(1 ether, 1 ether, 0, 0);
    mkr.newOffer(1 ether, 1 ether, 0, 0);
    overhead_gasbase = 21_000;
    offer_gasbase = 10_000;
    dex.setGasbase(_base, _quote, overhead_gasbase, offer_gasbase);
    tkr.marketOrder(0.1 ether, 0.1 ether);
    TestEvents.eq(
      dex.balanceOf(address(mkr)),
      1 ether - ((2 * overhead_gasbase) / 3 + offer_gasbase * 2) * 10**9,
      "Wrong gasbase deducted"
    );
  }

  function penalty_gasprice_is_dex_gasprice_test() public {
    dex.setGasprice(10);
    mkr.shouldFail(true);
    mkr.provisionDex(1 ether);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint oldProvision = dex.balanceOf(address(mkr));
    dex.setGasprice(10000);
    tkr.marketOrder(1 ether, 1 ether);
    uint gotBack = dex.balanceOf(address(mkr)) - oldProvision;
    TestEvents.eq(gotBack, 0, "Should not have gotten any provision back");
  }
}
