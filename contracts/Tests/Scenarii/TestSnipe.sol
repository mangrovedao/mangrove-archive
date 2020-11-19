import "../Toolbox/TestUtils.sol";
import "../Agents/MakerDeployer.sol";

library TestSnipe {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    Dex dex,
    MakerDeployer makers,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) external {
    uint orderAmount = 0.3 ether;
    uint snipedId = 2;
    TestMaker maker = makers.getMaker(snipedId); // maker whose offer will be sniped

    //(uint init_mkr_wants, uint init_mkr_gives,,,,,)=dex.getOfferInfo(2);
    //---------------SNIPE------------------//
    TestEvents.testTrue(
      TestUtils.snipeWithGas(taker, snipedId, orderAmount),
      "snipe should be a success"
    );
    TestEvents.testEq(
      aToken.balanceOf(address(dex)), //actual
      balances.dexBalanceFees + TestUtils.getFee(dex, orderAmount), //expected
      "incorrect Dex A balance"
    );
    TestEvents.testEq(
      bToken.balanceOf(address(taker)),
      balances.takerBalanceB -
        (orderAmount * offers[snipedId][TestUtils.Info.makerWants]) /
        offers[snipedId][TestUtils.Info.makerGives],
      "incorrect taker B balance"
    );
    TestEvents.testEq(
      aToken.balanceOf(address(taker)), // actual
      balances.takerBalanceA + orderAmount - TestUtils.getFee(dex, orderAmount), // expected
      "incorrect taker A balance"
    );
    TestEvents.testEq(
      aToken.balanceOf(address(maker)),
      balances.makersBalanceA[snipedId] - orderAmount,
      "incorrect maker A balance"
    );
    TestEvents.testEq(
      bToken.balanceOf(address(maker)),
      balances.makersBalanceB[snipedId] +
        (orderAmount * offers[snipedId][TestUtils.Info.makerWants]) /
        offers[snipedId][TestUtils.Info.makerGives],
      "incorrect maker B balance"
    );
    // Testing residual offer
    (bool exists, uint makerWants, uint makerGives, , , , , ) = dex
      .getOfferInfo(snipedId);
    TestEvents.TestTrue(exists, "Offer should have a residual");
    TestEvents.testEq(
      makerGives,
      offers[snipedId][TestUtils.Info.makerGives] - orderAmount,
      "Incorrect residual offer (gives)"
    );
    TestEvents.testEq(
      makerWants,
      (offers[snipedId][TestUtils.Info.makerWants] *
        (offers[snipedId][TestUtils.Info.makerGives] - orderAmount)) /
        offers[snipedId][TestUtils.Info.makerGives],
      "Incorrect residual offer (wants)"
    );
  }
}