import "../Toolbox/TestUtils.sol";

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

    evil.newOffer({wants: 1 ether, gives: 0.5 ether, gasreq: 7000, pivotId: 0});
    TestEvents.logString("+ Pushing 4 real offers and a dummy one", 1);
    Display.logOfferBook(dex, 5);
    uint[] memory failingOffers = dex.marketOrder({
      takerWants: 1 ether,
      takerGives: 10 ether,
      punishLength: 5,
      offerId: 0
    });
    //    for(uint i=0; i < failingOffers.length; i++){
    //      console.log("Offer failing: %d",failingOffers[i]);
    //    }
    Display.logOfferBook(dex, 5);

    // Display.printOfferBook(dex);
    // TODO test deepSnipe procedure
  }
}
