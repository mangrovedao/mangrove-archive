pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

abstract contract Persistent is MangroveOffer {
  function __postHookNoFailure__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
  {}

  //__postHookGetFailure__(uint missingAmount, order);
}
