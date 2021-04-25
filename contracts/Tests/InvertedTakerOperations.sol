// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../Dex.sol";
import {IMaker as IM, DexCommon} from "../DexCommon.sol";
import "../interfaces.sol";
import "hardhat/console.sol";

import "./Toolbox/TestEvents.sol";
import "./Toolbox/TestUtils.sol";
import "./Toolbox/Display.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";

/* The following constructs an ERC20 with a transferFrom callback method,
   and a TestTaker which throws away any funds received upon getting
   a callback.
*/
contract InvertedTakerOperations_Test is ITaker {
  TestToken baseT;
  TestToken quoteT;
  address base;
  address quote;
  Dex dex;
  TestMaker mkr;
  bytes4 takerTrade_bytes;
  uint baseBalance;
  uint quoteBalance;

  receive() external payable {}

  function a_beforeAll() public {
    baseT = TokenSetup.setup("A", "$A");
    quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    dex = DexSetup.setup(baseT, quoteT, true);

    mkr = MakerSetup.setup(dex, base, quote);

    address(mkr).transfer(10 ether);
    mkr.provisionDex(1 ether);
    mkr.approveDex(baseT, 10 ether);

    baseT.mint(address(mkr), 5 ether);
    quoteT.mint(address(this), 5 ether);
    quoteT.approve(address(dex), 5 ether);
    baseBalance = baseT.balanceOf(address(this));
    quoteBalance = quoteT.balanceOf(address(this));

    Display.register(msg.sender, "Test Runner");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(dex), "dex");
    Display.register(address(mkr), "maker");
  }

  uint toPay;

  function checkPay(
    address,
    address,
    uint totalGives
  ) external {
    TestEvents.eq(
      toPay,
      totalGives,
      "totalGives should be the sum of taker flashborrows"
    );
  }

  bool skipCheck;

  function takerTrade(
    address _base,
    address _quote,
    uint totalGot,
    uint totalGives
  ) public override {
    require(msg.sender == address(dex));
    if (!skipCheck) {
      TestEvents.eq(
        baseBalance + totalGot,
        baseT.balanceOf(address(this)),
        "totalGot should be sum of maker flashloans"
      );
    }
    (bool success, ) =
      address(this).call(
        abi.encodeWithSelector(takerTrade_bytes, _base, _quote, totalGives)
      );
    require(success, "TradeFail");
  }

  function taker_gets_sum_of_borrows_in_execute_test() public {
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    takerTrade_bytes = this.checkPay.selector;
    toPay = 0.2 ether;
    (, uint gave) = dex.marketOrder(base, quote, 0.2 ether, 0.2 ether);
    TestEvents.eq(
      quoteBalance - gave,
      quoteT.balanceOf(address(this)),
      "totalGave should be sum of taker flashborrows"
    );
  }

  function revertTrade(
    address,
    address,
    uint
  ) external pure {
    require(false);
  }

  function taker_reverts_during_trade_test() public {
    uint ofr = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    uint _ofr = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    takerTrade_bytes = this.revertTrade.selector;
    skipCheck = true;
    try dex.marketOrder(base, quote, 0.2 ether, 0.2 ether) {
      TestEvents.fail("Market order should have reverted");
    } catch Error(string memory reason) {
      TestEvents.eq("TradeFail", reason, "Unexpected throw");
      TestEvents.check(
        TestUtils.hasOffer(dex, address(base), address(quote), ofr),
        "Offer 1 should be present"
      );
      TestEvents.check(
        TestUtils.hasOffer(dex, address(base), address(quote), _ofr),
        "Offer 2 should be present"
      );
    }
  }

  function refuseFeeTrade(
    address _base,
    address,
    uint
  ) external {
    ERC20(_base).approve(address(dex), 0);
  }

  function refusePayTrade(
    address,
    address _quote,
    uint
  ) external {
    ERC20(_quote).approve(address(dex), 0);
  }

  function taker_refuses_to_deliver_during_trade_test() public {
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    takerTrade_bytes = this.refusePayTrade.selector;
    try dex.marketOrder(base, quote, 0.2 ether, 0.2 ether) {
      TestEvents.fail("Market order should have reverted");
    } catch Error(string memory reason) {
      TestEvents.eq(
        reason,
        "dex/takerFailToPayMaker",
        "Unexpected throw message"
      );
    }
  }

  function noop(
    address,
    address,
    uint
  ) external {}

  function reenter(
    address _base,
    address _quote,
    uint
  ) external {
    takerTrade_bytes = this.noop.selector;
    skipCheck = true;
    (bool success, uint totalGot, uint totalGave) =
      dex.snipe(_base, _quote, 2, 0.1 ether, 0.1 ether, 100_000);
    TestEvents.check(success, "Snipe on reentrancy should succeed");
    TestEvents.eq(totalGot, 0.1 ether, "Incorrect totalGot");
    TestEvents.eq(totalGave, 0.1 ether, "Incorrect totalGave");
  }

  function taker_snipe_dex_during_trade_test() public {
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    takerTrade_bytes = this.reenter.selector;
    (uint got, uint gave) = dex.marketOrder(base, quote, 0.1 ether, 0.1 ether);
    TestEvents.eq(
      quoteBalance - gave - 0.1 ether,
      quoteT.balanceOf(address(this)),
      "Incorrect transfer (gave) during reentrancy"
    );
    TestEvents.eq(
      baseBalance + got + 0.1 ether,
      baseT.balanceOf(address(this)),
      "Incorrect transfer (got) during reentrancy"
    );
    TestEvents.expectFrom(address(dex));
    emit DexEvents.Success(base, quote, 1, address(this), 0.1 ether, 0.1 ether);
    emit DexEvents.Success(base, quote, 2, address(this), 0.1 ether, 0.1 ether);
    TestEvents.expectFrom(address(mkr));
    mkr.logExecute(address(dex), base, quote, 1, 0.1 ether, 0.1 ether);
    mkr.logExecute(address(dex), base, quote, 2, 0.1 ether, 0.1 ether);
  }

  function taker_pays_back_correct_amount_1_test() public {
    uint ofr = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    uint bal = quoteT.balanceOf(address(this));
    takerTrade_bytes = this.noop.selector;
    dex.snipe(base, quote, ofr, 0.05 ether, 0.05 ether, 100_000);
    TestEvents.eq(
      quoteT.balanceOf(address(this)),
      bal - 0.05 ether,
      "wrong taker balance"
    );
  }

  function taker_pays_back_correct_amount_2_test() public {
    uint ofr = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    uint bal = quoteT.balanceOf(address(this));
    takerTrade_bytes = this.noop.selector;
    dex.snipe(base, quote, ofr, 0.02 ether, 0.05 ether, 100_000);
    TestEvents.eq(
      quoteT.balanceOf(address(this)),
      bal - 0.02 ether,
      "wrong taker balance"
    );
  }
}
