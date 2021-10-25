pragma solidity ^0.7.0;
pragma abicoder v2;
import "../../AaveTrader.sol";

contract AdvancedAaveRetail is AaveTrader(2) {
  constructor(address addressesProvider, address payable MGV)
    AaveLender(addressesProvider, 0)
    MangroveOffer(MGV)
  {}

  // Tries to take base directly from `this` balance. Fetches the remainder on Aave.
  function __get__(IERC20 outbound_tkn, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    uint missing = MangroveOffer.__get__(outbound_tkn, amount);
    if (missing > 0) {
      return super.__get__(outbound_tkn, missing);
    }
    return 0;
  }
}
