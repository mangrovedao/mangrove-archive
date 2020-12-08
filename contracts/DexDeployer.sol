// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./Dex.sol";
import "./interfaces.sol";
import "./lib/HasAdmin.sol";

contract DexDeployer is HasAdmin, IDeployer {
  mapping(address => mapping(address => address)) public dexes;
  mapping(address => mapping(address => address)) public invertedDexes;
  /* Configuration contract is called "Sauron". It is upgradeable. */
  ISauron public override sauron;

  constructor(ISauron _sauron) HasAdmin() {
    setSauron(_sauron);
  }

  function deploy(
    address ofrToken,
    address reqToken,
    bool takerLends
  ) external adminOnly returns (Dex) {
    /* When a new dex is deployed, its `density` is 1 by default and its `fee` is 0 (see `Sauron.sol`). Other parameters are global. */
    Dex dex = new Dex({takerLends: takerLends});

    dex.setAdmin(admin);

    mapping(address => mapping(address => address)) storage map =
      takerLends ? dexes : invertedDexes;

    require(
      map[ofrToken][reqToken] == address(0),
      "DexDeployer/alreadyDeployed"
    );
    map[ofrToken][reqToken] = address(dex);

    return dex;
  }

  function setSauron(ISauron _sauron) public adminOnly {
    sauron = _sauron;
  }
}
