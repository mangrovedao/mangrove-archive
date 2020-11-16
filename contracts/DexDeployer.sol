// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./Dex.sol";

contract DexDeployer {
  address public admin;
  mapping(address => mapping(address => Dex)) public dexes;

  constructor(address initialAdmin) {
    admin = initialAdmin;
  }

  function deploy(
    uint initialDustPerGasWanted,
    uint initialGasprice,
    uint initialGasmax,
    address ofrToken,
    address reqToken
  ) external returns (Dex) {
    require(isAdmin(msg.sender));

    Dex dex = new Dex(
      admin,
      initialDustPerGasWanted,
      initialGasprice,
      initialGasprice,
      initialGasmax,
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
