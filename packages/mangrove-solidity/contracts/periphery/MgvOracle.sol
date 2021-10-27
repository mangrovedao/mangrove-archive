pragma solidity ^0.7.0;
pragma abicoder v2;
import "../Strategies/lib/AccessControlled.sol";
import "../Mangrove.sol";
import "../MgvLib.sol";

/* The purpose of the Oracle contract is to act as a gas price and density
 * oracle for the Mangrove. It bridges to an external oracle, and allows
 * a given sender to update the gas price and density which the oracle
 * reports to Mangrove. */

//TODO: Should set the bot EOA as admin, and set authonly on setGasPrice?
contract MgvOracle is AccessControlled, IMgvMonitor {
  Mangrove immutable MGV;
  uint lastReceivedGasPrice;
  uint lastReceivedDensity;

  constructor(Mangrove _MGV) {
    MGV = _MGV;

    //NOTE: Hardwiring density for now
    lastReceivedDensity = type(uint).max;
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
    lastReceivedGasPrice = gasPrice;
  }

  //TODO: This should have the onlyAdmin or onlySender modifier
  function setDensity(uint density) private {
    //NOTE: Not implemented, so not made external yet
  }

  function read(address outbound_tkn, address inbound_tkn)
    external
    view
    override
    returns (uint gasprice, uint density)
  {
    return (lastReceivedGasPrice, lastReceivedDensity);
  }
}
