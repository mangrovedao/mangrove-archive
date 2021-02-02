// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../../DexCommon.sol";

contract DexOracle is IDexOracle {
  uint gasprice;
  uint density;

  function setGasprice(uint _gasprice) external {
    gasprice = _gasprice;
  }

  function setDensity(uint _density) external {
    density = _density;
  }

  function read(address base, address quote)
    external
    override
    returns (uint, uint)
  {
    return (gasprice, density);
  }
}
