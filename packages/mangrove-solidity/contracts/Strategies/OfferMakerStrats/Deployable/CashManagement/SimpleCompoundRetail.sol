pragma solidity ^0.7.0;
pragma abicoder v2;
import "../../CompoundLender.sol";

contract SimpleCompoundRetail is CompoundLender {
  constructor(
    address _unitroller,
    address payable _MGV,
    address wethAddress
  ) CompoundLender(_unitroller, wethAddress) MangroveOffer(_MGV) {}

  // Tries to take base directly from `this` balance. Fetches the remainder on Compound.
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
