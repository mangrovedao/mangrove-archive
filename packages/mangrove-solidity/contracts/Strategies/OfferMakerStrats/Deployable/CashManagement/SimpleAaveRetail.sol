pragma solidity ^0.7.0;
pragma abicoder v2;
import "../../AaveLender.sol";

contract SimpleAaveRetail is AaveLender {
  constructor(address _addressesProvider, address payable _MGV)
    AaveLender(_addressesProvider, 0)
    MangroveOffer(_MGV)
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
    // if not tries to fetch missing liquidity on compound using `AaveLender`'s strat
    return super.__get__(base, missingGet);
  }

  function __put__(IERC20 quote, uint amount) internal virtual override {
    // should check here if `this` contract has enough funds in `quote` token
    // TODO
    // transfers the remainder on Aave
    super.__put__(quote, amount);
  }
}
