// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./interfaces.sol";
import "./Dex.sol";
import "./Passthrough.sol";
import "hardhat/console.sol";

contract TestFailingMaker is IMaker, Passthrough {
  Dex dex;

  constructor(Dex _dex) {
    dex = _dex;
  }

  event Execute(
    uint takerWants,
    uint takerGives,
    uint penaltyPerGas,
    uint orderId
  );

  receive() external payable {}

  function execute(
    uint takerWants,
    uint takerGives,
    uint penaltyPerGas,
    uint orderId
  ) public override {
    emit Execute(takerWants, takerGives, penaltyPerGas, orderId);
    assert(false);
  }

  function newOrder(
    uint wants,
    uint gives,
    uint gasWanted,
    uint pivotId
  ) public returns (uint) {
    return (dex.newOrder(wants, gives, gasWanted, pivotId));
  }

  function provisionDex(uint amount) public {
    (bool success, ) = address(dex).call{value: amount}("");
    require(success);
  }

  function approve(IERC20 token, uint amount) public {
    token.approve(address(dex), amount);
  }
}
