// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
import "../Toolbox/TestUtils.sol";

library TestSnipe {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    Dex dex,
    MakerDeployer makers,
    TestTaker taker,
    TestToken base,
    TestToken quote
  ) external {
    uint orderAmount = 0.3 ether;
    uint snipedId = 2;
    TestMaker maker = makers.getMaker(snipedId); // maker whose offer will be sniped

    //(uint init_mkr_wants, uint init_mkr_gives,,,,,)=dex.getOfferInfo(2);
    //---------------SNIPE------------------//
    TestEvents.check(
      taker.take(snipedId, orderAmount),
      "snipe should be a success"
    );
    TestEvents.eq(
      base.balanceOf(TestUtils.adminOf(dex)), //actual
      balances.dexBalanceFees +
        TestUtils.getFee(dex, address(base), address(quote), orderAmount), //expected
      "incorrect Dex A balance"
    );
    TestEvents.eq(
      quote.balanceOf(address(taker)),
      balances.takerBalanceB -
        (orderAmount * offers[snipedId][TestUtils.Info.makerWants]) /
        offers[snipedId][TestUtils.Info.makerGives],
      "incorrect taker B balance"
    );
    TestEvents.eq(
      base.balanceOf(address(taker)), // actual
      balances.takerBalanceA +
        orderAmount -
        TestUtils.getFee(dex, address(base), address(quote), orderAmount), // expected
      "incorrect taker A balance"
    );
    TestEvents.eq(
      base.balanceOf(address(maker)),
      balances.makersBalanceA[snipedId] - orderAmount,
      "incorrect maker A balance"
    );
    TestEvents.eq(
      quote.balanceOf(address(maker)),
      balances.makersBalanceB[snipedId] +
        (orderAmount * offers[snipedId][TestUtils.Info.makerWants]) /
        offers[snipedId][TestUtils.Info.makerGives],
      "incorrect maker B balance"
    );
    // Testing residual offer
    (bool exists, uint makerWants, uint makerGives, , , , , ) =
      dex.getOfferInfo(address(base), address(quote), snipedId);
    TestEvents.check(!exists, "Offer should not have a residual");
  }
}
