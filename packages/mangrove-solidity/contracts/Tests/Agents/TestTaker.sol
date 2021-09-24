// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;
import "../../AbstractMangrove.sol";
import "./OfferManager.sol";

contract TestTaker is ITaker {
  AbstractMangrove _mgv;
  address _base;
  address _quote;

  constructor(
    AbstractMangrove mgv,
    IERC20 base,
    IERC20 quote
  ) {
    _mgv = mgv;
    _base = address(base);
    _quote = address(quote);
  }

  receive() external payable {}

  function approveMgv(IERC20 token, uint amount) external {
    token.approve(address(_mgv), amount);
  }

  function approveSpender(address spender, uint amount) external {
    _mgv.approve(_base, _quote, spender, amount);
  }

  function take(uint offerId, uint takerWants) external returns (bool success) {
    //uint taken = TestEvents.min(makerGives, takerWants);
    (success, , ) = _mgv.snipe(
      _base,
      _quote,
      offerId,
      takerWants,
      type(uint96).max, //takergives
      type(uint48).max, //gasreq
      true
    );
    //return taken;
  }

  function takeWithInfo(uint offerId, uint takerWants)
    external
    returns (
      bool,
      uint,
      uint
    )
  {
    //uint taken = TestEvents.min(makerGives, takerWants);
    return
      _mgv.snipe(
        _base,
        _quote,
        offerId,
        takerWants,
        type(uint96).max, //takergives
        type(uint48).max, //gasreq
        true
      );
    //return taken;
  }

  function snipe(
    AbstractMangrove __mgv,
    address __base,
    address __quote,
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint gasreq
  ) external returns (bool success) {
    (success, , ) = __mgv.snipe(
      __base,
      __quote,
      offerId,
      takerWants,
      takerGives,
      gasreq,
      true
    );
  }

  function takerTrade(
    address,
    address,
    uint,
    uint
  ) external pure override {}

  function marketOrder(uint wants, uint gives) external returns (uint, uint) {
    return _mgv.marketOrder(_base, _quote, wants, gives, true);
  }

  function marketOrder(
    AbstractMangrove __mgv,
    address __base,
    address __quote,
    uint takerWants,
    uint takerGives
  ) external returns (uint, uint) {
    return __mgv.marketOrder(__base, __quote, takerWants, takerGives, true);
  }

  function marketOrderWithFail(uint wants, uint gives)
    external
    returns (uint, uint)
  {
    return _mgv.marketOrder(_base, _quote, wants, gives, true);
  }
}