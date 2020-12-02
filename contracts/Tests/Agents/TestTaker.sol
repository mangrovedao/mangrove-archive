// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "../../interfaces.sol";
import "../../Dex.sol";

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
    //uint taken = TestEvents.min(makerGives, takerWants);
    success = dex.snipe(offerId, type(uint16).max, takerWants);
    //return taken;
  }

  function marketOrder(uint wants, uint gives) external override {
    dex.simpleMarketOrder(wants, gives);
  }

  function marketOrderWithFail(
    uint wants,
    uint gives,
    uint punishLength,
    uint offerId
  ) external returns (uint[2][] memory) {
    return (dex.marketOrder(wants, gives, punishLength, offerId));
  }

  function snipesAndRevert(uint[] calldata targets, uint punishLength)
    external
  {
    dex.punishingSnipes(targets, punishLength);
  }

  function marketOrderAndRevert(
    uint fromOfferId,
    uint takerWants,
    uint takerGives,
    uint punishLength
  ) external {
    dex.punishingMarketOrder(fromOfferId, takerWants, takerGives, punishLength);
  }
}
