// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./interfaces.sol";
import "./Dex.sol";
import "./Passthrough.sol";
import "@nomiclabs/buidler/console.sol";

contract TestMaker is IMaker, Passthrough {
  Dex dex;

  constructor(Dex _dex) {
    dex = _dex;
  }

  function execute(
    uint,
    uint,
    uint,
    uint orderId
  ) public view override {
    console.log("\t !! Maker is being called for order %d", orderId);
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

  receive() external payable {}
}
