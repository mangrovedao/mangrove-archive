// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./Dex.sol";

contract DexDeployer {
  address public admin;
  mapping(IERC20 => mapping(IERC20 => Dex)) public dexes;

  constructor(address initialAdmin) {
    admin = initialAdmin;
  }

  function deploy(
    uint initialDustPerGasWanted,
    uint initialMinFinishGas,
    uint initialPenaltyPerGas,
    uint initialMinGasWanted,
    IERC20 ofrToken,
    IERC20 reqToken
  ) external returns (Dex) {
    require(isAdmin(msg.sender));

    Dex dex = new Dex(
      admin,
      initialDustPerGasWanted,
      initialMinFinishGas,
      initialPenaltyPerGas,
      initialMinGasWanted,
      ofrToken,
      reqToken
    );

    dexes[ofrToken][reqToken] = dex;

    return dex;
  }

  function isAdmin(address maybeAdmin) internal view returns (bool) {
    return maybeAdmin == admin;
  }

  function updateAdmin(address newValue) external {
    if (isAdmin(msg.sender)) {
      admin = newValue;
    }
  }
}
