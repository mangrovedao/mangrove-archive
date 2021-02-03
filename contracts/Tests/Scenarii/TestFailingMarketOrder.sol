// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma abicoder v2;
import "../Toolbox/TestUtils.sol";

library TestFailingMarketOrder {
  function moWithFailures(
    Dex dex,
    address base,
    address quote,
    TestTaker taker
  ) external {
    (, , uint[2][] memory failures) =
      taker.marketOrderWithFail({
        wants: 10 ether,
        gives: 30 ether,
        punishLength: 10,
        offerId: dex.best(base, quote)
      });
    uint failedOffer = 1;
    for (uint i = 0; i < failures.length; i++) {
      TestEvents.eq(failures[i][0], failedOffer, "Incorrect failed offer Id");
      TestEvents.less(
        failures[i][1],
        100000 + uint(dex.config(base, quote).local.gasbase),
        "Incorrect Gas consummed"
      );
      failedOffer++;
    }
    TestEvents.check(
      TestUtils.isEmptyOB(dex, base, quote),
      "Offer book should be empty"
    );
  }

  function snipesAndRevert(
    Dex dex,
    address base,
    address quote,
    TestTaker taker
  ) external {
    uint tkrBalance = address(taker).balance;
    uint[4][] memory targetsOK = new uint[4][](5);
    uint[4][] memory targetsWrong = new uint[4][](5);
    //offerId, takerWants, takerGives, gasreq

    uint cpt = 0;
    for (uint i = 5; i > 0; i--) {
      targetsOK[cpt] = [i, 0.5 ether, 100 ether, 1_000_000];
      targetsWrong[cpt] = [cpt + 1, 0.5 ether, 100 ether, 1_000_000];
      cpt++;
    }
    // if offers are not consumed starting by offer 5 (best)
    // no offer fails and the OB should be unchanged
    taker.snipesAndRevert(targetsWrong, 5);
    for (uint i = 1; i <= 5; i++) {
      TestEvents.check(
        TestUtils.hasOffer(dex, base, quote, i),
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
      TestUtils.hasOffer(dex, base, quote, 5),
      "Dummy offer should still be in OB"
    );
    for (uint i = 1; i < 5; i++) {
      TestEvents.check(
        !TestUtils.hasOffer(dex, base, quote, i),
        Display.append(
          "Failing offer ",
          Display.uint2str(i),
          " should have been removed from OB"
        )
      );
    }
    TestEvents.eq(
      address(taker).balance, //actual
      tkrBalance + 4 * TestUtils.getProvision(dex, base, quote, 100000),
      "Incorrect taker balance"
    );
  }

  function moAndRevert(
    Dex dex,
    address base,
    address quote,
    TestTaker tkr
  ) external {
    uint tkrBalance = address(tkr).balance;
    tkr.marketOrderAndRevert(dex.best(base, quote), 10 ether, 30 ether, 10);
    TestEvents.check(
      TestUtils.hasOffer(dex, base, quote, 5),
      "Dummy offer should still be in OB"
    );
    for (uint i = 1; i < 5; i++) {
      TestEvents.check(
        !TestUtils.hasOffer(dex, base, quote, i),
        Display.append(
          "Failing offer ",
          Display.uint2str(i),
          " should have been removed from OB"
        )
      );
    }
    TestEvents.eq(
      address(tkr).balance, //actual
      tkrBalance + 4 * TestUtils.getProvision(dex, base, quote, 100000),
      "Incorrect taker balance"
    );
  }
}
