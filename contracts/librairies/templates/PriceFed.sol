pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "../../SafeMath.sol";

abstract contract PriceFed is MangroveOffer {
  // function should be called during a makerTrade execution
  function __trade_checkPrice(
    MgvC.SingleOrder calldata order,
    uint quote_price, // amount of quote token for 1e18 base
    uint slippage_num, // with slippage num/den considered_price is offer_price + (offer_price*num) / den
    uint slippage_den
  ) internal pure returns (TradeResult, bytes32) {
    // `quote_price` is the suggested amount of quote in exchange of 1e18 base token (exaunits)
    // [TODO] rounding error management needed
    uint slippage =
      SafeMath.div(SafeMath.mul(slippage_num, order.gives), slippage_den);
    uint oracle_price =
      SafeMath.div(SafeMath.mul(quote_price, order.wants), 1e18);
    if (oracle_price > order.gives + slippage) {
      return (TradeResult.Drop, bytes32(quote_price));
    } else {
      return (TradeResult.Proceed, bytes32(quote_price));
    }
  }
}
