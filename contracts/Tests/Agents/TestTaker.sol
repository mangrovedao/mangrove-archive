// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "../../interfaces.sol";
import "../../Dex.sol";
import "./OfferManager.sol";
import "./TestToken.sol";

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
    _dex.simpleMarketOrder(_base, _quote, wants, gives);
  }

  function marketOrderWithFail(
    uint wants,
    uint gives,
    uint punishLength,
    uint offerId
  ) external returns (uint[2][] memory fails) {
    (, , fails) = _dex.marketOrder(
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

  function delegateOrder(
    OfferManager mgr,
    uint wants,
    uint gives
  ) public {
    try IERC20(_quote).approve(address(mgr), gives) {
      console.log("Delegate order");
      address(mgr).call{value: 0.01 ether}(
        abi.encodeWithSelector(mgr.order.selector, _base, _quote, wants, gives)
      );
    } catch {
      require(false, "failed to approve mgr");
    }
  }
}
