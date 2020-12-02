// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
import "../Toolbox/TestUtils.sol";

library TestFailingMarketOrder {
  function moWithFailures(Dex dex, TestTaker taker) external {
    uint[] memory failures =
      taker.marketOrderWithFail({
        wants: 10 ether,
        gives: 30 ether,
        punishLength: 10,
        offerId: dex.getBest()
      });
    uint failedOffer = 1;
    for (uint i = 0; i < failures.length - 1; i += 2) {
      TestEvents.eq(failures[i], failedOffer, "Incorrect failed offer Id");
      TestEvents.less(
        failures[i + 1],
        100000 + dex.getConfigUint(DC.ConfigKey.gasbase),
        "Incorrect Gas consummed"
      );
      failedOffer++;
    }
    TestEvents.check(TestUtils.isEmptyOB(dex), "Offer book should be empty");
  }

  function snipesAndRevert(Dex dex, TestTaker taker) external {
    uint tkrBalance = address(taker).balance;
    uint[] memory targetsOK = new uint[](10);
    uint[] memory targetsWrong = new uint[](10);

    uint cpt = 0;
    for (uint i = 5; i > 0; i--) {
      targetsOK[2 * cpt] = i;
      targetsWrong[2 * cpt] = cpt + 1;
      targetsOK[2 * cpt + 1] = 0.5 ether;
      targetsWrong[2 * cpt + 1] = 0.5 ether;
      cpt++;
    }
    // if offers are not consumed in the order given by OB
    // no offer fails and the OB should be unchanged
    taker.snipesAndRevert(targetsWrong, 5);
    for (uint i = 1; i <= 5; i++) {
      TestEvents.check(
        TestUtils.hasOffer(dex, i),
        Display.append(
          "Offer ",
          Display.uint2str(i),
          " should have been kept in OB"
        )
      );
    }
    TestEvents.eq(
      address(taker).balance, //actual
      tkrBalance,
      "Incorrect taker balance"
    );

    // sniping offers in the OB order.
    taker.snipesAndRevert(targetsOK, 5);
    // Display.logOfferBook(dex,5);
    // check that dummy offer is still there:
    TestEvents.check(
      TestUtils.hasOffer(dex, 5),
      "Dummy offer should still be in OB"
    );
    for (uint i = 1; i < 5; i++) {
      TestEvents.check(
        !TestUtils.hasOffer(dex, i),
        Display.append(
          "Failing offer ",
          Display.uint2str(i),
          " should have been removed from OB"
        )
      );
    }
    TestEvents.eq(
      address(taker).balance, //actual
      tkrBalance + 4 * TestUtils.getProvision(dex, 100000),
      "Incorrect taker balance"
    );
  }

  function moAndRevert(Dex dex, TestTaker tkr) external {
    uint tkrBalance = address(tkr).balance;
    tkr.marketOrderAndRevert(dex.getBest(), 10 ether, 30 ether, 10);
    TestEvents.check(
      TestUtils.hasOffer(dex, 5),
      "Dummy offer should still be in OB"
    );
    for (uint i = 1; i < 5; i++) {
      TestEvents.check(
        !TestUtils.hasOffer(dex, i),
        Display.append(
          "Failing offer ",
          Display.uint2str(i),
          " should have been removed from OB"
        )
      );
    }
    Display.logOfferBook(dex, 5);
    TestEvents.eq(
      address(tkr).balance, //actual
      tkrBalance + 4 * TestUtils.getProvision(dex, 100000),
      "Incorrect taker balance"
    );
  }
}
