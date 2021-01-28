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
    TestToken base,
    TestToken quote
  ) external {
    try wrongOwner.deleteOffer(offerId) {
      TestEvents.fail("Invalid authorization to cancel order");
    } catch Error(string memory reason) {
      TestEvents.eq(reason, "dex/cancelOffer/unauthorized", "Unexpected throw");
      try maker.deleteOffer(offerId) {
        maker.deleteOffer(0);
        uint provisioned =
          TestUtils.getProvision(
            dex,
            address(base),
            address(quote),
            offers[offerId][TestUtils.Info.gasreq]
          );
        TestEvents.eq(
          dex.balanceOf(address(maker)),
          balances.makersBalanceWei[offerId] + provisioned,
          "Incorrect returned provision to maker"
        );
      } catch {
        TestEvents.fail("Cancel order failed unexpectedly");
      }
    }
  }
}
