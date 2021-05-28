pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

abstract contract PriceFed is MangroveOffer {
  struct Slippage {
    uint128 units;
    uint128 base;
  }
  Slippage slippage = Slippage({
      units: uint128(0),
      base: uint128(1)
    }); // no slippage by default

  constructor() {}

  // `slippage` is in per `slippage_base`
  // if x quotes is the price for 1 base, then `(x-slippage*slippage_base)/slippage_base` is allowed
  function set_slippage(uint new_units, uint new_base)
    external
    onlyCaller(admin)
  {
    require( uint128(new_units)==new_units && uint128(new_base)==new_base && new_base > 0, "Invalid slippage params");
    slippage.units = uint128(new_units);
    slippage.base = uint128(new_base);
    log("Slippage",new_units,new_base);
  }

  // function should be called during a makerTrade execution
  function __trade_checkPrice(MgvC.SingleOrder calldata order, uint quote_price)
    internal
    returns (TradeResult, bytes32)
  {
    // `quote_price` is the suggested amount of quote in exchange of 1 base
    // [TODO] rounding error management needed
    uint offered_price =
      (order.gives * slippage.base + slippage.units) / slippage.base;
    if (quote_price * order.wants > offered_price) {
      return (TradeResult.Drop, bytes32(quote_price));
    } else {
      return (TradeResult.Proceed, bytes32(quote_price));
    }
  }
}
