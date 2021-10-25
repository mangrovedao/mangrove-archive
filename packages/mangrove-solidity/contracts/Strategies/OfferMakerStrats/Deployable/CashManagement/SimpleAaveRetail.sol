pragma solidity ^0.7.0;
pragma abicoder v2;
import "../../AaveLender.sol";

contract SimpleAaveRetail is AaveLender {
  constructor(address _addressesProvider, address payable _MGV)
    AaveLender(_addressesProvider, 0)
    MangroveOffer(_MGV)
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
