pragma solidity ^0.7.0;
pragma abicoder v2;
import "../Strategies/lib/AccessControlled.sol";
import "../Mangrove.sol";
import "../MgvLib.sol";

//TODO: Currently doesn't use *any* math, if it does use CarefulMath
contract MgvGasUpdater is AccessControlled {
  Mangrove immutable MGV;

  constructor(Mangrove _MGV) {
    MGV = _MGV;
  }

  //TODO: Is it really this simple? And if so, how much is gained by having a separate contract for this? Maybe this should rather be a `MgvConfig` contract?
  //TODO: Should this have the onlyAdmin modifier?
  function setGasPrice(uint gasPrice) external {
    MGV.setGasprice(gasPrice);
  }
}
