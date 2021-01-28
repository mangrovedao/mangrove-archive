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

contract MakerPosthook_Test is IMaker {
  Dex dex;
  TestTaker tkr;
  TestToken baseT;
  TestToken quoteT;
  address base;
  address quote;
  uint gasreq = 200_000;
  uint ofr;
  bytes4 posthook_bytes;
  uint gasprice = 50; // will cover for a gasprice of 50 gwei/gas uint
  uint weiBalMaker;
  bool abort = false;

  receive() external payable {}

  function makerTrade(DexCommon.SingleOrder calldata trade, address taker)
    external
    override
    returns (bytes32)
  {
    require(msg.sender == address(dex));
    if (abort) {
      return ("NOK");
    }
    emit Execute(
      msg.sender,
      trade.base,
      trade.quote,
      trade.offerId,
      trade.wants,
      trade.gives
    );
    TestToken(trade.base).transfer(taker, trade.wants);
    return ("OK");
  }

  function renew_offer_at_posthook(
    DexCommon.SingleOrder calldata order,
    DexCommon.OrderResult calldata
  ) external {
    require(msg.sender == address(this));
    dex.updateOffer(
      order.base,
      order.quote,
      1 ether,
      1 ether,
      gasreq,
      gasprice,
      order.offerId,
      order.offerId
    );
  }

  function update_gas_offer_at_posthook(
    DexCommon.SingleOrder calldata order,
    DexCommon.OrderResult calldata
  ) external {
    require(msg.sender == address(this));
    dex.updateOffer(
      order.base,
      order.quote,
      1 ether,
      1 ether,
      gasreq,
      gasprice,
      order.offerId,
      order.offerId
    );
  }

  function failer_posthook(
    DexCommon.SingleOrder calldata,
    DexCommon.OrderResult calldata
  ) external {
    require(msg.sender == address(this));
    TestEvents.fail("Posthook should not be called");
  }

  function deleteOffer_posthook(
    DexCommon.SingleOrder calldata,
    DexCommon.OrderResult calldata
  ) external {
    require(msg.sender == address(this));
    uint bal = dex.balanceOf(address(this));
    dex.retractOffer(base, quote, ofr, true);
    if (abort) {
      TestEvents.eq(
        bal,
        dex.balanceOf(address(this)),
        "Cancel offer of a failed offer should not give provision to maker"
      );
    }
  }

  function makerPosthook(
    DexCommon.SingleOrder calldata order,
    DexCommon.OrderResult calldata result
  ) external override {
    require(msg.sender == address(dex));
    TestEvents.check(
      !TestUtils.hasOffer(dex, order.base, order.quote, order.offerId),
      "Offer was not removed after take"
    );
    address(this).call(abi.encodeWithSelector(posthook_bytes, order, result));
  }

  function a_beforeAll() public {
    Display.register(address(this), "Test runner");

    baseT = TokenSetup.setup("A", "$A");
    quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    Display.register(base, "base");
    Display.register(quote, "quote");

    dex = DexSetup.setup(baseT, quoteT);
    Display.register(address(dex), "Dex");

    tkr = TakerSetup.setup(dex, base, quote);
    Display.register(address(tkr), "Taker");

    address(tkr).transfer(10 ether);
    quoteT.mint(address(tkr), 1 ether);
    baseT.mint(address(this), 5 ether);

    tkr.approveDex(baseT, 1 ether); // takerFee
    tkr.approveDex(quoteT, 1 ether);

    dex.fund{value: 10 ether}(address(this)); // for new offer and further updates
    weiBalMaker = dex.balanceOf(address(this));
  }

  function renew_offer_after_partial_fill_test() public {
    uint mkr_provision =
      TestUtils.getProvision(dex, base, quote, gasreq, gasprice);
    posthook_bytes = this.renew_offer_at_posthook.selector;

    ofr = dex.newOffer(base, quote, 1 ether, 1 ether, gasreq, gasprice, 0);

    TestEvents.eq(
      dex.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    bool success = tkr.take(ofr, 0.5 ether);
    TestEvents.check(success, "Snipe should succeed");

    TestEvents.eq(
      dex.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    TestEvents.eq(
      TestUtils.getOfferInfo(dex, base, quote, TestUtils.Info.makerGives, ofr),
      1 ether,
      "Offer was not correctly updated"
    );
    TestEvents.expectFrom(address(dex));
    emit DexEvents.WriteOffer(
      base,
      quote,
      address(this),
      DexPack.writeOffer_pack(1 ether, 1 ether, gasprice, gasreq, ofr)
    );
  }

  function renew_offer_after_complete_fill_test() public {
    uint mkr_provision =
      TestUtils.getProvision(dex, base, quote, gasreq, gasprice);
    posthook_bytes = this.renew_offer_at_posthook.selector;

    ofr = dex.newOffer(base, quote, 1 ether, 1 ether, gasreq, gasprice, 0);

    TestEvents.eq(
      dex.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(success, "Snipe should succeed");

    TestEvents.eq(
      dex.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    TestEvents.eq(
      TestUtils.getOfferInfo(dex, base, quote, TestUtils.Info.makerGives, ofr),
      1 ether,
      "Offer was not correctly updated"
    );
    TestEvents.expectFrom(address(dex));
    emit DexEvents.WriteOffer(
      base,
      quote,
      address(this),
      DexPack.writeOffer_pack(1 ether, 1 ether, gasprice, gasreq, ofr)
    );
  }

  function renew_offer_after_failed_execution_test() public {
    posthook_bytes = this.renew_offer_at_posthook.selector;

    ofr = dex.newOffer(base, quote, 1 ether, 1 ether, gasreq, gasprice, 0);
    abort = true;

    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(!success, "Snipe should fail");

    TestEvents.eq(
      TestUtils.getOfferInfo(dex, base, quote, TestUtils.Info.makerGives, ofr),
      1 ether,
      "Offer was not correctly updated"
    );
    TestEvents.expectFrom(address(dex));
    emit DexEvents.WriteOffer(
      base,
      quote,
      address(this),
      DexPack.writeOffer_pack(1 ether, 1 ether, gasprice, gasreq, ofr)
    );
  }

  function update_offer_with_more_gasprice_test() public {
    uint mkr_provision =
      TestUtils.getProvision(dex, base, quote, gasreq, gasprice);
    uint standard_provision = TestUtils.getProvision(dex, base, quote, gasreq);
    posthook_bytes = this.update_gas_offer_at_posthook.selector;
    // provision for dex.global.gasprice
    ofr = dex.newOffer(base, quote, 1 ether, 1 ether, gasreq, 0, 0);

    TestEvents.eq(
      dex.balanceOf(address(this)),
      weiBalMaker - standard_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(success, "Snipe should succeed");

    TestEvents.eq(
      dex.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    TestEvents.eq(
      TestUtils.getOfferInfo(dex, base, quote, TestUtils.Info.makerGives, ofr),
      1 ether,
      "Offer was not correctly updated"
    );
    TestEvents.expectFrom(address(dex));
    emit DexEvents.WriteOffer(
      base,
      quote,
      address(this),
      DexPack.writeOffer_pack(1 ether, 1 ether, gasprice, gasreq, ofr)
    );
  }

  function posthook_of_skipped_offer_wrong_gas_should_not_be_called_test()
    public
  {
    posthook_bytes = this.failer_posthook.selector;

    ofr = dex.newOffer(base, quote, 1 ether, 1 ether, gasreq, gasprice, 0);

    bool success =
      tkr.snipe(dex, base, quote, ofr, 1 ether, 1 ether, gasreq - 1);
    TestEvents.check(!success, "Snipe should fail");
  }

  function posthook_of_skipped_offer_wrong_price_should_not_be_called_test()
    public
  {
    posthook_bytes = this.failer_posthook.selector;
    ofr = dex.newOffer(base, quote, 1 ether, 1 ether, gasreq, gasprice, 0);
    bool success = tkr.snipe(dex, base, quote, ofr, 1.1 ether, 1 ether, gasreq);
    TestEvents.check(!success, "Snipe should fail");
  }

  function delete_offer_in_posthook_test() public {
    uint mkr_provision =
      TestUtils.getProvision(dex, base, quote, gasreq, gasprice);
    posthook_bytes = this.deleteOffer_posthook.selector;
    ofr = dex.newOffer(base, quote, 1 ether, 1 ether, gasreq, gasprice, 0);
    TestEvents.eq(
      dex.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(success, "Snipe should succeed");
    TestEvents.eq(
      dex.balanceOf(address(this)),
      weiBalMaker, // provision returned to taker
      "Incorrect maker balance after take"
    );
    TestEvents.expectFrom(address(dex));
    emit DexEvents.Success(base, quote, ofr, 1 ether, 1 ether);
    emit DexEvents.Credit(address(this), mkr_provision);
    emit DexEvents.DeleteOffer(base, quote, ofr);
  }

  function delete_offer_after_fail_in_posthook_test() public {
    uint mkr_provision =
      TestUtils.getProvision(dex, base, quote, gasreq, gasprice);
    posthook_bytes = this.deleteOffer_posthook.selector;
    ofr = dex.newOffer(base, quote, 1 ether, 1 ether, gasreq, gasprice, 0);
    TestEvents.eq(
      dex.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    abort = true; // maker should fail
    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(!success, "Snipe should fail");

    TestEvents.less(
      dex.balanceOf(address(this)),
      weiBalMaker,
      "Maker balance after take should be less than original balance"
    );
    uint refund = dex.balanceOf(address(this)) + mkr_provision - weiBalMaker;
    TestEvents.expectFrom(address(dex));
    emit DexEvents.MakerFail(
      base,
      quote,
      ofr,
      1 ether,
      1 ether,
      false,
      bytes32("NOK")
    );
    emit DexEvents.DeleteOffer(base, quote, ofr);
    DexEvents.Credit(address(this), refund);
  }
}