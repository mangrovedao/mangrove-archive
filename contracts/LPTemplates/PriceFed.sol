pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "./PriceOracle.sol";
import "../MgvPack.sol";

abstract contract PriceFed is MangroveOffer {
  PriceOracle pf_oracle;
  uint pf_slippage;
  uint pf_slippage_base;

  bytes32 immutable VALIDPRICE = "ValidPrice";
  bytes32 immutable INVALIDPRICE = "InvalidPrice";

  constructor(
    address payable mgv,
    address base_erc,
    address oracle,
    uint slippage,
    uint slippage_base
  ) MangroveOffer(mgv, base_erc) {
    pf_oracle = PriceOracle(oracle);
    pf_slippage = slippage;
    pf_slippage_base = slippage_base;
  }

  // `slippage` is in per `slippage_base`
  // if x quotes is the price for 1 base, then `(x-slippage*slippage_base)/slippage_base` is allowed
  function set_slippage(uint new_slippage, uint new_base)
    external
    onlyCaller(admin)
  {
    pf_slippage = new_slippage;
    pf_slippage_base = new_base;
  }

  // Mangrove trade management

  // Function that verifies that the pool is sufficiently provisioned
  // throws otherwise
  // Note that the order.gives is NOT verified
  function PriceFedTrade(MgvC.SingleOrder calldata order)
    internal
    returns (bytes32 ret)
  {
    // `quote_price` is the suggested amount of quote in exchange of 1 base
    // [TODO] rounding error management needed
    uint quote_price = pf_oracle.get_quote_for(order.quote);
    uint offered_price =
      (order.gives * pf_slippage_base + pf_slippage) / pf_slippage_base;
    if (quote_price * order.wants > offered_price) {
      tradeRevert(bytes32(quote_price)); //sending quote_price to posthook
    } else {
      ret = VALIDPRICE;
    }
  }

  function PriceFedPosthook(
    MgvC.SingleOrder calldata order,
    MgvC.OrderResult calldata result
  ) internal {
    if (!result.success) {
      uint quote_price = uint(result.makerData);
      uint new_wants = quote_price * mo_gives;
      updateMangroveOffer(order.quote, new_wants, 0, order.offerId);
    }
  }
}
