pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

abstract contract Persistent is MangroveOffer {
  struct Persistent_env {
    uint8 slippage;
    uint160 slippage_base;
  }
  Persistent_env persistent_env;

  constructor(
    address payable mgv,
    address base_erc,
    uint _slippage,
    uint _slippage_base
  ) MangroveOffer(mgv, base_erc) {
    persistent_env = Persistent_env({
      slippage: uint8(_slippage),
      slippage_base: uint160(_slippage_base)
    });
  }

  // `slippage` is in per `slippage_base`
  // if x quotes is the price for 1 base, then `(x-slippage*slippage_base)/slippage_base` is allowed
  function set_slippage(uint new_slippage, uint new_base)
    external
    onlyCaller(admin)
  {
    persistent_env.slippage = uint8(new_slippage);
    persistent_env.slippage_base = uint160(new_base);
    log("Slippage",new_slippage,new_base);
  }

  // function should be called during a makerTrade execution
  function __trade_checkPrice(MgvC.SingleOrder calldata order, uint quote_price)
    internal
    returns (TradeResult, bytes32)
  {
    // `quote_price` is the suggested amount of quote in exchange of 1 base
    // [TODO] rounding error management needed
    uint offered_price =
      (order.gives * persistent_env.slippage_base + persistent_env.slippage) /
        persistent_env.slippage_base;
    if (quote_price * order.wants > offered_price) {
      return (TradeResult.Drop, bytes32(quote_price));
    } else {
      return (TradeResult.Proceed, bytes32(quote_price));
    }
  }

  // function should be called during a posthook execution
  function __posthook_repostOfferAtPrice(
    MgvC.SingleOrder calldata order,
    uint quote_price
  ) internal {
    uint new_wants = quote_price * mangroveOffer_env.gives;
    // update offer with new price (with mangroveOffer_env.gives) and pivotId 0
    updateMangroveOffer(order.quote, new_wants, 0, order.offerId);
  }
}
