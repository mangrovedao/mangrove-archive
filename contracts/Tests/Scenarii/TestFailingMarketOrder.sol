// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;
import "../Toolbox/TestUtils.sol";

library TestFailingMarketOrder {
  function moWithFailures(
    Dex dex,
    address base,
    address quote,
    TestTaker taker
  ) external {
    taker.marketOrderWithFail({
      wants: 10 ether,
      gives: 30 ether,
      offerId: dex.bests(base, quote)
    });
    TestEvents.check(
      TestUtils.isEmptyOB(dex, base, quote),
      "Offer book should be empty"
    );
  }
}
