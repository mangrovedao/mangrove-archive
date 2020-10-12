// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./interfaces.sol";
import "./Dex.sol";
import "./Passthrough.sol";

contract TestMoriartyMaker is IMaker, Passthrough {
  Dex dex;
  bool shouldFail;

  constructor(Dex _dex) {
    dex = _dex;
    shouldFail = false;
  }

  function execute(
    uint256,
    uint256,
    uint256,
    uint256
  ) public override {
    if (shouldFail) {
      // second call to execute always fails
      assert(false);
    } else {
      shouldFail = true;
    }
  }

  function newOrder(
    uint256 wants,
    uint256 gives,
    uint256 gasWanted,
    uint256 pivotId
  ) public returns (uint256) {
    uint256 orderId = (dex.newOrder(wants, gives, gasWanted, pivotId));
    uint256 minDustPerGas = dex.dustPerGasWanted();
    dex.newOrder(0, minDustPerGas, 1, 0);
    return orderId;
  }

  function provisionDex(uint256 amount) public {
    (bool success, ) = address(dex).call{value: amount}("");
    require(success);
  }

  function approve(IERC20 token, uint256 amount) public {
    token.approve(address(dex), amount);
  }

  receive() external payable {}
}
