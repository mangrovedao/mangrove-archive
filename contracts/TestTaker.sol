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

  function approve(IERC20 token, uint amount) external {
    token.approve(address(dex), amount);
  }

  function take(uint orderId, uint wants) external override {
    dex.snipe(orderId, wants);
  }

  function mo(uint wants, uint gives) external override {
    dex.conditionalMarketOrder(wants, gives);
  }
}
