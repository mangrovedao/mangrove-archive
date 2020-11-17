// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./interfaces.sol";
import "./Dex.sol";
import "./DexCommon.sol";
import "./Passthrough.sol";

contract TestMoriartyMaker is IMaker, Passthrough {
  Dex dex;
  bool succeed;

  constructor(Dex _dex) {
    dex = _dex;
    succeed = true;
  }

  function execute(
    uint,
    uint,
    uint,
    uint
  ) public override {
    require(succeed);
    succeed = false;
  }

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public returns (uint) {
    uint offerId = (dex.newOffer(wants, gives, gasreq, pivotId));
    uint density = dex.getConfigUint(ConfigKey.density);
    uint gasbase = dex.getConfigUint(ConfigKey.gasbase);
    dex.newOffer(0, density * (gasbase + 1), 1, 0); //dummy offer
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
