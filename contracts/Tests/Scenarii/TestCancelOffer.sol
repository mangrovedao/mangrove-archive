// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
import "../Toolbox/TestUtils.sol";

library TestCancelOffer {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    Dex dex,
    TestMaker wrongOwner,
    TestMaker maker,
    uint offerId,
    TestTaker, /* taker */
    TestToken aToken,
    TestToken bToken
  ) external {
    try wrongOwner.cancelOffer(dex, offerId) returns (uint) {
      TestEvents.fail("Invalid authorization to cancel order");
    } catch Error(string memory reason) {
      TestEvents.eq(reason, "dex/cancelOffer/unauthorized", "Unexpected throw");
      try maker.cancelOffer(dex, offerId) returns (uint released) {
        require(maker.cancelOffer(dex, 0) == 0); // should be no-op
        TestEvents.eq(
          released,
          TestUtils.getProvision(
            dex,
            address(aToken),
            address(bToken),
            offers[offerId][TestUtils.Info.gasreq]
          ),
          "Incorrect released amount"
        );
        TestEvents.eq(
          dex.balanceOf(address(maker)),
          balances.makersBalanceWei[offerId] + released,
          "Incorrect returned provision to maker"
        );
      } catch {
        TestEvents.fail("Cancel order failed unexpectedly");
      }
    }
  }
}
