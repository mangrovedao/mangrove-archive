// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;
import "../../interfaces.sol";
import "../../Dex.sol";
import "./OfferManager.sol";

contract TestTaker is ITaker {
  Dex _dex;
  address _base;
  address _quote;

  constructor(
    Dex dex,
    IERC20 base,
    IERC20 quote
  ) {
    _dex = dex;
    _base = address(base);
    _quote = address(quote);
  }

  receive() external payable {}

  function approveDex(IERC20 token, uint amount) external {
    token.approve(address(_dex), amount);
  }

  function take(uint offerId, uint takerWants) external returns (bool success) {
    //uint taken = TestEvents.min(makerGives, takerWants);
    (success, , ) = _dex.snipe(
      _base,
      _quote,
      offerId,
      takerWants,
      type(uint96).max, //takergives
      type(uint48).max //gasreq
    );
    //return taken;
  }

  function snipe(
    Dex __dex,
    address __base,
    address __quote,
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint gasreq
  ) external returns (bool success) {
    (success, , ) = __dex.snipe(
      __base,
      __quote,
      offerId,
      takerWants,
      takerGives,
      gasreq
    );
  }

  function takerTrade(
    address,
    address,
    uint,
    uint
  ) external pure override {}

  function marketOrder(uint wants, uint gives) external {
    _dex.simpleMarketOrder(_base, _quote, wants, gives);
  }

  function simpleMarketOrder(
    Dex __dex,
    address __base,
    address __quote,
    uint takerWants,
    uint takerGives
  ) external {
    __dex.simpleMarketOrder(__base, __quote, takerWants, takerGives);
  }

  function marketOrderWithFail(
    uint wants,
    uint gives,
    uint punishLength,
    uint offerId
  ) external returns (uint[2][] memory failures) {
    (, , failures) = _dex.marketOrder(
      _base,
      _quote,
      wants,
      gives,
      punishLength,
      offerId
    );
  }

  function snipesAndRevert(uint[4][] calldata targets, uint punishLength)
    external
  {
    _dex.punishingSnipes(_base, _quote, targets, punishLength);
  }

  function marketOrderAndRevert(
    uint fromOfferId,
    uint takerWants,
    uint takerGives,
    uint punishLength
  ) external {
    _dex.punishingMarketOrder(
      _base,
      _quote,
      fromOfferId,
      takerWants,
      takerGives,
      punishLength
    );
  }
}
