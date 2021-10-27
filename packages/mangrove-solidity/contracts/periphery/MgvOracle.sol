pragma solidity ^0.7.0;
pragma abicoder v2;
import "../Strategies/lib/AccessControlled.sol";
import "../Mangrove.sol";
import "../MgvLib.sol";

/* TODO: Add nice description and usage instructions
 *
 *  */

//TODO: Should set the bot EOA as admin, and set authonly on setGasPrice?
contract MgvOracle is AccessControlled, IMgvMonitor {
  Mangrove immutable MGV;
  uint receivedGasPrice;

  constructor(Mangrove _MGV) {
    MGV = _MGV;
  }

  function notifySuccess(MgvLib.SingleOrder calldata sor, address taker)
    external
    override
  {
    // Do nothing
  }

  function notifyFail(MgvLib.SingleOrder calldata sor, address taker)
    external
    override
  {
    // Do nothing
  }

  //TODO: This should have the onlyAdmin or onlySender modifier
  function setGasPrice(uint gasPrice) external {
    receivedGasPrice = gasPrice;
  }

  function read(address outbound_tkn, address inbound_tkn)
    external
    view
    override
    returns (uint gasprice, uint density)
  {
    return (receivedGasPrice, type(uint).max);
  }
}
