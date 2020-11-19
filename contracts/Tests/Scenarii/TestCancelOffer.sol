import "../Toolbox/TestEvents.sol";
import "../Toolbox/TestUtils.sol";

library TestCancelOffer {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    Dex dex,
    TestMaker wrongOwner,
    TestMaker maker,
    uint offerId,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) external {
    try wrongOwner.cancelOffer(dex, offerId) returns (uint) {
      TestEvents.testFail("Invalid authorization to cancel order");
    } catch Error(string memory reason) {
      TestEvents.testEq(reason, "dex/unauthorizedCancel", "Unexpected throw");
      try maker.cancelOffer(dex, offerId) returns (uint released) {
        TestEvents.testEq(
          released,
          TestUtils.getProvision(dex, offers[offerId][TestUtils.Info.gasreq]),
          "Incorrect released amount"
        );
        TestEvents.testEq(
          dex.balanceOf(address(maker)),
          balances.makersBalanceWei[offerId] + released,
          "Incorrect returned provision to maker"
        );
      } catch (bytes memory errorMsg) {
        TestEvents.testFail("Cancel order failed unexpectedly");
      }
    }
  }
}
