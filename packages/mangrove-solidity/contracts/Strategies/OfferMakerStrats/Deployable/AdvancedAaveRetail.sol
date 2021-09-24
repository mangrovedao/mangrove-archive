pragma solidity ^0.7.0;
pragma abicoder v2;
import "../AaveTrader.sol";

contract AdvancedAaveRetail is AaveTrader(2) {
  constructor(address addressesProvider, address payable MGV)
    AaveLender(addressesProvider, 0)
    MangroveOffer(MGV)
  {}

  // Tries to take base directly from `this` balance. Fetches the remainder on Aave.
  function __get__(IERC20 base, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    // checks whether `this` contract has enough `base` token
    uint missingGet = MangroveOffer.__get__(base, amount);
    // if not tries to fetch missing liquidity on compound using `AaveTrader`'s strat
    return super.__get__(base, missingGet);
  }

  function __put__(IERC20 quote, uint amount) internal virtual override {
    super.__put__(quote, amount);
  }
}
