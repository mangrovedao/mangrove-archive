import "../Toolbox/TestUtils.sol";
import "../Agents/MakerDeployer.sol";

library TestMarketOrder {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    Dex dex,
    MakerDeployer makers,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) external {
    uint takerWants = 1.6 ether; // of B token
    uint takerGives = 2 ether; // of A token

    TestUtils.marketOrderWithGas(taker, takerWants, takerGives);

    // Checking Makers balances
    for (uint i = 2; i < 4; i++) {
      // offers 2 and 3 were consumed entirely
      Test.eq(
        aToken.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceA[i] - offers[i][TestUtils.Info.makerGives],
        Display.append("Incorrect A balance for maker ", Display.uint2str(i))
      );
      Test.eq(
        bToken.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceB[i] + offers[i][TestUtils.Info.makerWants],
        Display.append("Incorrect B balance for maker ", Display.uint2str(i))
      );
    }
    uint leftTkrWants = takerWants -
      (offers[2][TestUtils.Info.makerGives] +
        offers[3][TestUtils.Info.makerGives]);
    uint leftMkrWants = (offers[1][TestUtils.Info.makerWants] * leftTkrWants) /
      offers[1][TestUtils.Info.makerGives];

    Test.eq(
      aToken.balanceOf(address(makers.getMaker(1))),
      balances.makersBalanceA[1] - leftTkrWants,
      "Incorrect A balance for maker 1"
    );
    Test.eq(
      bToken.balanceOf(address(makers.getMaker(1))),
      balances.makersBalanceB[1] + leftMkrWants,
      "Incorrect B balance for maker 1"
    );

    // Checking taker balance
    Test.eq(
      aToken.balanceOf(address(taker)), // actual
      balances.takerBalanceA + takerWants - TestUtils.getFee(dex, takerWants), // expected
      "incorrect taker A balance"
    );

    Test.eq(
      bToken.balanceOf(address(taker)), // actual
      balances.takerBalanceB -
        (offers[3][TestUtils.Info.makerWants] +
          offers[2][TestUtils.Info.makerWants] +
          leftMkrWants), // expected
      "incorrect taker B balance"
    );

    // Checking DEX Fee Balance
    Test.eq(
      aToken.balanceOf(address(dex)), //actual
      balances.dexBalanceFees + TestUtils.getFee(dex, takerWants), //expected
      "incorrect Dex balances"
    );
  }
}
