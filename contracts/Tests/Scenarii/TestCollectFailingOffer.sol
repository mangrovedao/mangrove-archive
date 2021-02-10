// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;
import "../Toolbox/TestUtils.sol";

library TestCollectFailingOffer {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    Dex dex,
    uint failingOfferId,
    MakerDeployer makers,
    TestTaker taker,
    TestToken base,
    TestToken quote
  ) external {
    // executing failing offer
    try taker.takeWithInfo(failingOfferId, 0.5 ether) returns (
      bool success,
      uint takerGot,
      uint takerGave
    ) {
      // take should return false not throw
      TestEvents.check(!success, "Failer should fail");
      TestEvents.eq(takerGot, 0, "Failed offer should declare 0 takerGot");
      TestEvents.eq(takerGave, 0, "Failed offer should declare 0 takerGave");
      // failingOffer should have been removed from Dex
      {
        (bool exists, , ) =
          DexIt.getOfferInfo(
            dex,
            address(base),
            address(quote),
            failingOfferId
          );
        TestEvents.check(
          (!exists),
          "Failing offer should have been removed from Dex"
        );
      }
      uint provision =
        TestUtils.getProvision(
          dex,
          address(base),
          address(quote),
          offers[failingOfferId][TestUtils.Info.gasreq]
        );
      uint returned =
        dex.balanceOf(address(makers.getMaker(0))) -
          balances.makersBalanceWei[0];
      TestEvents.eq(
        address(dex).balance,
        balances.dexBalanceWei - (provision - returned),
        "Dex has not send the correct amount to taker"
      );
    } catch (bytes memory errorMsg) {
      string memory err = abi.decode(errorMsg, (string));
      TestEvents.fail(err);
    }
  }
}
