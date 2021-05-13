// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;
import "../Toolbox/TestUtils.sol";

library TestFailingMarketOrder {
  function moWithFailures(
    Mangrove mgv,
    address base,
    address quote,
    TestTaker taker
  ) external {
    taker.marketOrderWithFail({wants: 10 ether, gives: 30 ether});
    TestEvents.check(
      TestUtils.isEmptyOB(mgv, base, quote),
      "Offer book should be empty"
    );
  }
}
