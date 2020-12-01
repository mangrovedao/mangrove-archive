// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./Dex.sol";
import "./lib/HasAdmin.sol";

contract DexDeployer is HasAdmin {
  mapping(address => mapping(address => address)) public dexes;
  mapping(address => mapping(address => address)) public invertedDexes;

  constructor() HasAdmin() {
    
  }

  function deploy(
    uint density,
    uint gasprice,
    uint gasbase,
    uint gasmax,
    address ofrToken,
    address reqToken,
    bool takerLends
  ) external adminOnly returns (Dex) {

    Dex dex = new Dex({
      _density: density,
      _gasprice: gasprice,
      _gasbase: gasbase,
      _gasmax: gasmax,
      _OFR_TOKEN: ofrToken,
      _REQ_TOKEN: reqToken,
      takerLends: takerLends
    });

    dex.setAdmin(admin);
    
    mapping (address => mapping(address => address)) storage map = takerLends ? dexes : invertedDexes;

    require(map[ofrToken][reqToken] == address(0), "DexDeployer/alreadyDeployed");
    map[ofrToken][reqToken] = address(dex);

    return dex;
  }
}
