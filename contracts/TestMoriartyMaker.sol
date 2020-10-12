// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./interfaces.sol";
import "./Dex.sol";
import "./Passthrough.sol";

contract TestMoriartyMaker is IMaker, Passthrough {
  Dex dex;
  mapping(uint256 => bool) private shouldFail;

  constructor(Dex _dex) {
    dex = _dex;
  }

  function execute(
    uint256 takerWants,
    uint256 takerGives,
    uint256 orderPenaltyPerGas,
    uint256 orderId
  ) public override {}

  function newOrder(
    uint256 wants,
    uint256 gives,
    uint256 gasWanted,
    uint256 pivotId
  ) public returns (uint256) {
    uint256 orderId = (dex.newOrder(wants, gives, gasWanted, pivotId));
    uint256 minDustPerGas = dex.dustPerGastWanted();
    uint256 dummyOrder = dex.newOrder(0, minDustPerGas, 1, 0);
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
