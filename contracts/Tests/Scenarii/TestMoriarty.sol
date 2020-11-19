import "../../Dex.sol";
import "../Agents/TestToken.sol";
import "../Agents/TestTaker.sol";
import "../Agents/TestMoriartyMaker.sol";
import "../Toolbox/Display.sol";

library TestMoriarty {
  function run(
    Dex dex,
    TestTaker taker,
    TestToken aToken,
    TestToken bToken
  ) external {
    TestMoriartyMaker evil = new TestMoriartyMaker(dex);
    Display.register(address(evil), "Moriarty");

    (bool success, ) = address(evil).call{gas: gasleft(), value: 20 ether}(""); // msg.value is distributed evenly amongst makers
    require(success, "maker transfer");
    evil.provisionDex(10 ether);
    aToken.mint(address(evil), 5 ether);
    evil.approve(aToken, 5 ether);

    uint offerId = evil.newOffer({
      wants: 1 ether,
      gives: 0.5 ether,
      gasreq: 7000,
      pivotId: 0
    });
    taker.marketOrder({wants: 1 ether, gives: 1 ether});
    // Display.printOfferBook(dex);
    // TODO test deepSnipe procedure
  }
}
