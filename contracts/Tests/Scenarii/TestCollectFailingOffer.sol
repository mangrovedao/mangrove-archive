// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
import "../Toolbox/TestUtils.sol";

library TestCollectFailingOffer {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    Dex dex,
    uint failingOfferId,
    MakerDeployer makers,
    TestTaker taker,
    TestToken, /* aToken */ // silence warning about unused argument
    TestToken /* bToken */ // silence warning about unused argument
  ) external {
    // executing failing offer
    try taker.take(failingOfferId, 0.5 ether) returns (bool success) {
      // take should return false not throw
      TestEvents.check(!success, "Failer should fail");
      // failingOffer should have been removed from Dex
      (bool exists, , , , , , , ) = dex.getOfferInfo(failingOfferId);
      TestEvents.check(
        !exists,
        "Failing offer should have been removed from Dex"
      );
      uint returned = dex.balanceOf(address(makers.getMaker(0))) -
        balances.makersBalanceWei[0];
      uint provision = TestUtils.getProvision(
        dex,
        offers[failingOfferId][TestUtils.Info.gasreq]
      );
      TestEvents.eq(
        address(dex).balance,
        balances.dexBalanceWei - (provision - returned),
        "Dex has not send enough money to taker"
      );
    } catch (bytes memory errorMsg) {
      string memory err = abi.decode(errorMsg, (string));
      TestEvents.fail(err);
    }
  }
}
