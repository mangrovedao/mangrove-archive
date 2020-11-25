// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./Dex.sol";

contract DexDeployer {
  address public admin;
  mapping(address => mapping(address => Dex)) public dexes;
  mapping(address => mapping(address => Dex)) public invertedDexes;

  constructor(address _admin) {
    admin = _admin;
  }

  function requireAdmin() internal view {
    require(msg.sender == admin, "DexDeployer/adminOnly");
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
    requireAdmin();

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

  function updateAdmin(address _admin) external {
    requireAdmin();
    admin = _admin;
  }
}
