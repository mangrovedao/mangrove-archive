// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
import "../Toolbox/TestUtils.sol";

library TestFailingMarketOrder {
  function run(
    Dex dex,
    TestTaker taker,
    TestToken aToken
  ) external {
    uint[] memory failures = taker.probeForFail({
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

  function runAndRevert(
    Dex dex,
    TestTaker taker,
    TestToken aToken
  ) external {
    Display.logOfferBook(dex,5);
    uint tkrBalance = address(taker).balance;
    uint[] memory targets = new uint[](10);
    uint cpt = 0;
    for (uint i = 5; i > 0; i--) {
      targets[2 * cpt] = i;
      targets[2 * cpt + 1] = 0.5 ether;
      cpt++;
    }
    taker.snipeForFail(targets, 5);
    // check that dummy offer is still there:
    TestEvents.check(
      TestUtils.hasOffer(dex, 5),
      "Dummy offer should still be in OB"
    );
    for (uint i = 1; i < 5; i++) {
      TestEvents.check(
        !TestUtils.hasOffer(dex, i),
        "Failing offer should have been removed from OB"
      );
    }
    Display.logOfferBook(dex,5);
    TestEvents.eq(
      address(taker).balance,
      tkrBalance + 4 * TestUtils.getProvision(dex, 100000),
      "Incorrect taker balance"
    );
  }
}
