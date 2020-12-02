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
    TestToken, /* aToken */
    TestToken /* bToken */ // silence warnings about unused arguments
  ) external {
    try wrongOwner.cancelOffer(dex, offerId) {
      TestEvents.fail("Invalid authorization to cancel order");
    } catch Error(string memory reason) {
      TestEvents.eq(reason, "dex/cancelOffer/unauthorized", "Unexpected throw");
      try maker.cancelOffer(dex, offerId) {
        maker.cancelOffer(dex, 0);
        uint provisioned =
          TestUtils.getProvision(dex, offers[offerId][TestUtils.Info.gasreq]);
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
