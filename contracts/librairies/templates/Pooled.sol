pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

abstract contract Pooled is MangroveOffer {
  // returns (Proceed,balance Left) + (Drop, Missing Balance)
  function trade_checkLiquidity(MgvC.SingleOrder calldata order)
    internal
    view
    returns (TradeResult, bytes32)
  {
    uint pool_balance = IERC20(BASE_ERC).balanceOf(address(this));
    if (order.wants <= pool_balance) {
      return (TradeResult.Proceed, bytes32(pool_balance - order.wants));
    } else {
      return (TradeResult.Drop, bytes32(order.wants - pool_balance));
    }
  }
}
