pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "./PriceOracle.sol";

abstract contract LastLook is MangroveOffer {
  PriceOracle price_oracle;
  uint allowed_slippage;

  constructor(
    address payable _mgv,
    address _liquidity_source,
    uint _gas_to_execute,
    uint _gasprice_level,
    address _price_oracle,
    uint slippage
  ) MangroveOffer(_mgv,_liquidity_source,_gas_to_execute,_gasprice_level) {
    price_oracle = PriceOracle(_price_oracle);
    allowed_slippage = slippage;
  }

  function set_slippage(uint new_slippage) external onlyCaller(admin) {
    allowed_slippage = new_slippage;
  }

  // Mangrove trade management

  // Function that verifies that the pool is sufficiently provisioned
  // throws otherwise
  // Note that the order.gives is NOT verified
  function makerTrade(MgvC.SingleOrder calldata order)
    public
    override
    onlyCaller(address(mgv))
    returns (bytes32 ret)
  {
    // `quote_price` is the suggested amount of quote in exchange of `order.wants`
    // [TODO] rounding error management needed
    uint quote_price = price_oracle.get_price_for(order.quote);
    if (quote_price * order.wants  <= order.gives + allowed_slippage) {
      _makerTrade(order); // try to fullfill order (might fail if liquidity cannot be found)
    }
    else {
      tradeRevert(bytes32(quote_price)); //sending quote_price to posthook
    }
  }

  function makerPosthook(
    MC.SingleOrder calldata order,
    MC.OrderResult calldata result
  ) external override {
    // todo repost offer using new price if trade has failed
  }

}
