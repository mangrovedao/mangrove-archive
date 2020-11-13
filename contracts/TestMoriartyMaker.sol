// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./interfaces.sol";
import "./Dex.sol";
import "./DexCommon.sol";
import "./Passthrough.sol";

contract TestMoriartyMaker is IMaker, Passthrough {
  Dex dex;
  bool shouldFail;

  constructor(Dex _dex) {
    dex = _dex;
    shouldFail = false;
  }

  function execute(
    uint,
    uint,
    uint,
    uint
  ) public override {
    if (shouldFail) {
      // second call to execute always fails
      assert(false);
    } else {
      shouldFail = true; //consumes dummy offer
    }
  }

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public returns (uint) {
    uint offerId = (dex.newOffer(wants, gives, gasreq, pivotId));
    uint minDustPerGas = dex.getConfigUint(ConfigKey.density);
    dex.newOffer(0, minDustPerGas, 1, 0); //dummy offer
    return offerId;
  }

  function provisionDex(uint amount) public {
    (bool success, ) = address(dex).call{value: amount}("");
    require(success);
  }

  function approve(IERC20 token, uint amount) public {
    token.approve(address(dex), amount);
  }

  receive() external payable {}
}
