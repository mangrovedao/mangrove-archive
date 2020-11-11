// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
import "./interfaces.sol";
import "./Test.sol";
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

  function take(uint offerId, uint takerWants)
    external
    override
    returns (bool success)
  {
    //uint taken = Test.min(makerGives, takerWants);
    bool success = dex.snipe(offerId, takerWants);
    return success;
    //return taken;
  }

  function marketOrder(uint wants, uint gives) external override {
    dex.simpleMarketOrder(wants, gives);
  }
}
