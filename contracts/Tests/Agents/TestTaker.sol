// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "../../interfaces.sol";
import "../../Dex.sol";
import "./OfferManager.sol";

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

  function take(uint offerId, uint takerWants) external returns (bool success) {
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

  function takerTrade(
    address,
    address,
    uint,
    uint
  ) external pure override {}

  function marketOrder(uint wants, uint gives) external {
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

  function delegateOrder(
    OfferManager mgr,
    uint wants,
    uint gives
  ) public {
    try IERC20(quote).approve(address(mgr), gives) {
      console.log("Delegate order");
      mgr.order{value: 0.01 ether}(base, quote, wants, gives);
    } catch {
      require(false, "failed to approve mgr");
    }
  }
}
