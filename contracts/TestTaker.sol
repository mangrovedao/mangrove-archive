// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
import "./interfaces.sol";
import "./Dex.sol";

contract TestTaker is ITaker {
  Dex dex;

  constructor(Dex _dex) {
    dex = _dex;
  }

  receive() external payable {}

  function approve(IERC20 token, uint256 amount) external {
    token.approve(address(dex), amount);
  }

  function take(uint256 orderId, uint256 wants) external override {
    dex.externalExecuteOrder(orderId, wants);
  }
}
