// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
import "../Toolbox/TestUtils.sol";

library TestMoriarty {
  function run(
    Dex dex,
    TestTaker taker,
    TestToken aToken,
    TestToken /* bToken */ // silence warning about unused argument
  ) external {
    TestMoriartyMaker evil = new TestMoriartyMaker(dex);
    Display.register(address(evil), "Moriarty");

    (bool success, ) = address(evil).call{gas: gasleft(), value: 20 ether}(""); // msg.value is distributed evenly amongst makers
    require(success, "maker transfer");
    evil.provisionDex(10 ether);
    aToken.mint(address(evil), 5 ether);
    evil.approve(aToken, 5 ether);

    evil.newOffer({
      wants: 1 ether,
      gives: 0.5 ether,
      gasreq: 100000,
      pivotId: 0
    });

    TestEvents.logString("+ Pushing 4 real offers and a dummy one", 1);
    Display.printOfferBook(dex);
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
  }
}
