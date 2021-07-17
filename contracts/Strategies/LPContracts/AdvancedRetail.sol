pragma solidity ^0.7.0;
pragma abicoder v2;
import "./CompoundTrader.sol";

contract AdvancedRetail is CompoundTrader {
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
    uint missingGet = MangroveOffer.__get__(base, amount);
    return super.__get__(base, missingGet);
  }

  function __put__(IERC20 quote, uint amount) internal virtual override {
    super.__put__(quote, amount);
  }
}
