// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./interfaces.sol";
import "./Dex.sol";
import "./Passthrough.sol";

contract TestMaker is IMaker, Passthrough {
  Dex dex;

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
    return (dex.newOrder(wants, gives, gasWanted, pivotId));
  }

  function fund(uint256 amount) public {
    (bool success, ) = address(dex).call{value: amount}("");
    require(success);
  }

  function approve(IERC20 token, uint256 amount) public {
    token.approve(address(dex), amount);
  }

  receive() external payable {}
}
