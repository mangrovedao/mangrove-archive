pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "../lib/OpenOraclePriceData.sol";

// SPDX-License-Identifier: MIT

contract Defensive is MangroveOffer, Exponential, OpenOraclePriceData {
  OpenOraclePriceData immutable priceFeed;
  address immutable trustedSource;
  address constant coinbaseReporter =
    0xfCEAdAFab14d46e20144F48824d0C09B1a03F2BC;

  constructor(
    address _priceFeed,
    address _trustedSource,
    address payable _MGV
  ) MangroveOffer(_MGV) {
    priceFeed = OpenOraclePriceData(_priceFeed);
    trustedSource = _trustedSource;
  }

  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    override
    returns (uint)
  {
    IERC20 base = IERC20(order.base);
    IERC20 quote = IERC20(order.quote);
    uint usd_wanted =
      mul_( //amount of base tokens required by taker (in ~USD, 6 decimals)
        order.wants,
        uint(priceFeed.getPrice(trustedSource, base.symbol())) //could be checking age of the time stamp of data
      );
    uint usd_given =
      mul_( //amount of quote tokens given by taker (in ~USD, 6 decimals)
        order.gives,
        uint(priceFeed.getPrice(trustedSource, quote.symbol()))
      );

    // oracle_price = usd_given/usd_wanted, order_price = order.gives/order.wants
    // if oracle_price < offer_price return true
    // else if order_price - oracle_price <= oracle_price * slippage (in %) return true (a)
    // else return false
    // (a) is iff usd_given * order.wants - usd_wanted * order.gives > order.wants * order.gives * slippage * 10^slippage_decimals
    return 0;
  }
}
