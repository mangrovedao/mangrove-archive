// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "../Toolbox/TestUtils.sol";

library TestInsert {
  function run(
    TestUtils.Balances storage balances,
    Dex dex,
    MakerDeployer makers,
    TestTaker, /* taker */ // silence warning about unused argument
    TestToken, /* aToken */ // silence warning about unused argument
    TestToken /* bToken */ // silence warning about unused argument
  ) public returns (uint[] memory) {
    // each maker publishes an offer
    uint[] memory offerOf = new uint[](makers.length());
    console.log("Test insert with %d makers", makers.length());
    offerOf[1] = TestUtils.newOfferWithGas({
      maker: makers.getMaker(1),
      wants: 1 ether,
      gives: 0.5 ether,
      gasreq: 7000,
      pivotId: 0
    });
    offerOf[2] = TestUtils.newOfferWithGas({
      maker: makers.getMaker(2),
      wants: 1 ether,
      gives: 0.8 ether,
      gasreq: 8000,
      pivotId: 1
    });
    offerOf[3] = TestUtils.newOfferWithGas({
      maker: makers.getMaker(3),
      wants: 1 ether,
      gives: 0.8 ether,
      gasreq: 7999, // should beat offer 2 thx to low gas
      pivotId: 72
    });
    offerOf[0] = TestUtils.newOfferWithGas({
      maker: makers.getMaker(0), //failer
      wants: 20 ether,
      gives: 10 ether,
      gasreq: dex.getConfigUint(DC.ConfigKey.gasmax),
      pivotId: 0
    });
    //Display.printOfferBook(dex);
    //Checking makers have correctly provisoned their offers
    for (uint i = 0; i < makers.length(); i++) {
      uint gasreq_i =
        TestUtils.getOfferInfo(dex, TestUtils.Info.gasreq, offerOf[i]);
      uint provision_i = TestUtils.getProvision(dex, gasreq_i);
      TestEvents.eq(
        dex.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceWei[i] - provision_i,
        Display.append("Incorrect wei balance for maker ", Display.uint2str(i))
      );
    }
    Display.logOfferBook(dex, 5);
    //Checking offers are correctly positioned (3 > 2 > 1 > 0)
    uint offerId = dex.best();
    uint expected_maker = 3;
    while (offerId != 0) {
      (DC.Offer memory offer, DC.OfferDetail memory od) =
        dex.getOfferInfo(offerId, true);
      TestEvents.eq(
        od.maker,
        address(makers.getMaker(expected_maker)),
        Display.append(
          "Incorrect maker address at offer ",
          Display.uint2str(offerId)
        )
      );

      expected_maker -= 1;
      offerId = offer.next;
    }
    return offerOf;
  }
}
