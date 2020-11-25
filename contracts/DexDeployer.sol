// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./Dex.sol";

contract DexDeployer {
  address public admin;
  mapping(address => mapping(address => Dex)) public dexes;
  mapping(address => mapping(address => Dex)) public invertedDexes;

  constructor(address initialAdmin) {
    admin = initialAdmin;
  }

  function deploy(
    uint density,
    uint gasprice,
    uint gasbase,
    uint gasmax,
    address ofrToken,
    address reqToken,
    bool takerLends
  ) external returns (Dex) {
    require(isAdmin(msg.sender));

    Dex dex = new Dex({
      _admin: admin,
      _density: density,
      _gasprice: gasprice,
      _gasbase: gasbase,
      _gasmax: gasmax,
      _OFR_TOKEN: ofrToken,
      _REQ_TOKEN: reqToken,
      takerLends: takerLends
    });
    
    mapping (address => mapping(address => Dex)) storage map = takerLends ? dexes : invertedDexes;

    require(address(map[ofrToken][reqToken]) != address(0), "DexDeployer/alreadyDeployed");
    map[ofrToken][reqToken] = dex;

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
