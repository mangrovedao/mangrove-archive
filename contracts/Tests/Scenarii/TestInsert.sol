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
    TestToken base,
    TestToken quote
  ) public returns (uint[] memory) {
    // each maker publishes an offer
    uint[] memory offerOf = new uint[](makers.length());
    offerOf[1] = makers.getMaker(1).newOffer({
      wants: 1 ether,
      gives: 0.5 ether,
      gasreq: 50_000,
      pivotId: 0
    });
    offerOf[2] = makers.getMaker(2).newOffer({
      wants: 1 ether,
      gives: 0.8 ether,
      gasreq: 80_000,
      pivotId: 1
    });
    offerOf[3] = makers.getMaker(3).newOffer({
      wants: 0.5 ether,
      gives: 1 ether,
      gasreq: 90_000,
      pivotId: 72
    });
    offerOf[0] = makers.getMaker(0).newOffer({ //failer
      wants: 20 ether,
      gives: 10 ether,
      gasreq: dex.config(address(base), address(quote)).gasmax,
      pivotId: 0
    });
    //Display.printOfferBook(dex);
    //Checking makers have correctly provisoned their offers
    for (uint i = 0; i < makers.length(); i++) {
      uint gasreq_i =
        TestUtils.getOfferInfo(
          dex,
          address(base),
          address(quote),
          TestUtils.Info.gasreq,
          offerOf[i]
        );
      uint provision_i =
        TestUtils.getProvision(dex, address(base), address(quote), gasreq_i);
      TestEvents.eq(
        dex.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceWei[i] - provision_i,
        Display.append("Incorrect wei balance for maker ", Display.uint2str(i))
      );
    }
    //Checking offers are correctly positioned (3 > 2 > 1 > 0)
    uint offerId = dex.bests(address(base), address(quote));
    uint expected_maker = 3;
    while (offerId != 0) {
      (DC.Offer memory offer, DC.OfferDetail memory od) =
        dex.getOfferInfo(address(base), address(quote), offerId, true);
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
