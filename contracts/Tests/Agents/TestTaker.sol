// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "../../interfaces.sol";
import "../../Dex.sol";

contract TestTaker is ITaker {
  Dex dex;
  address base;
  address quote;

  constructor(
    Dex _dex,
    address _base,
    address _quote
  ) {
    dex = _dex;
    base = _base;
    quote = _quote;
  }

  receive() external payable {}

  function approveDex(IERC20 token, uint amount) external {
    token.approve(address(dex), amount);
  }

  function take(uint offerId, uint takerWants)
    external
    override
    returns (bool success)
  {
    //uint taken = TestEvents.min(makerGives, takerWants);
    success = dex.snipe(
      base,
      quote,
      offerId,
      takerWants,
      type(uint96).max,
      type(uint48).max
    );
    //return taken;
  }

  function marketOrder(uint wants, uint gives) external override {
    dex.simpleMarketOrder(base, quote, wants, gives);
  }

  function marketOrderWithFail(
    uint wants,
    uint gives,
    uint punishLength,
    uint offerId
  ) external returns (uint[2][] memory) {
    return (dex.marketOrder(base, quote, wants, gives, punishLength, offerId));
  }

  function snipesAndRevert(uint[4][] calldata targets, uint punishLength)
    external
  {
    dex.punishingSnipes(base, quote, targets, punishLength);
  }

  function marketOrderAndRevert(
    uint fromOfferId,
    uint takerWants,
    uint takerGives,
    uint punishLength
  ) external {
    dex.punishingMarketOrder(
      base,
      quote,
      fromOfferId,
      takerWants,
      takerGives,
      punishLength
    );
  }
}
