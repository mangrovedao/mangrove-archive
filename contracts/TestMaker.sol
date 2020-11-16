// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./interfaces.sol";
import "./Dex.sol";
import "./Passthrough.sol";
import "hardhat/console.sol";

contract TestMaker is IMaker, Passthrough {
  Dex dex;
  bool shouldFail;

  constructor(Dex _dex, bool _failer) {
    dex = _dex;
    shouldFail = _failer;
  }

  event Execute(uint takerWants, uint takerGives, uint gasprice, uint offerId);

  receive() external payable {}

  function execute(
    uint takerWants,
    uint takerGives,
    uint gasprice,
    uint offerId
  ) public override {
    emit Execute(takerWants, takerGives, gasprice, offerId);
    require(!shouldFail);
  }

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public returns (uint) {
    return (dex.newOffer(wants, gives, gasreq, pivotId));
  }

  function provisionDex(uint amount) public {
    (bool success, ) = address(dex).call{value: amount}("");
    require(success);
  }

  function approve(IERC20 token, uint amount) public {
    token.approve(address(dex), amount);
  }
}
