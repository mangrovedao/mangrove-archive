pragma solidity ^0.7.0;
pragma abicoder v2;
import "../CompoundTrader.sol";

contract AdvancedCompoundRetail is CompoundTrader {
  constructor(
    address _unitroller,
    address payable _MGV,
    address wethAddress
  ) CompoundTrader(_unitroller, _MGV, wethAddress) {}

  // Tries to take base directly from `this` balance. Fetches the remainder on Compound.
  function __get__(IERC20 base, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    // checks whether `this` contract has enough `base` token
    uint missingGet = MangroveOffer.__get__(base, amount);
    // if not tries to fetch missing liquidity on compound using `CompoundTrader`'s strat
    return super.__get__(base, missingGet);
  }

  function __put__(IERC20 quote, uint amount) internal virtual override {
    // should check here if `this` contract has enough funds in `quote` token
    // TODO
    // transfers the remainder on compound
    super.__put__(quote, amount);
  }
}
