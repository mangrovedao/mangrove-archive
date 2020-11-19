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
      Test.fail("Invalid authorization to cancel order");
    } catch Error(string memory reason) {
      Test.eq(reason, "dex/unauthorizedCancel", "Unexpected throw");
      try maker.cancelOffer(dex, offerId) returns (uint released) {
        Test.eq(
          released,
          TestUtils.getProvision(dex, offers[offerId][TestUtils.Info.gasreq]),
          "Incorrect released amount"
        );
        Test.eq(
          dex.balanceOf(address(maker)),
          balances.makersBalanceWei[offerId] + released,
          "Incorrect returned provision to maker"
        );
      } catch (bytes memory errorMsg) {
        Test.fail("Cancel order failed unexpectedly");
      }
    }
  }
}
