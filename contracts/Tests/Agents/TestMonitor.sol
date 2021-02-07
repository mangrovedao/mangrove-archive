// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../../DexCommon.sol";

library L {
  event TradeSuccess(DexCommon.SingleOrder order, address taker);
  event TradeFail(DexCommon.SingleOrder order);
}

contract DexMonitor is IDexMonitor {
  uint gasprice;
  mapping(address => mapping(address => uint)) private densities;

  function setGasprice(uint _gasprice) external {
    gasprice = _gasprice;
  }

  function setDensity(
    address base,
    address quote,
    uint _density
  ) external {
    densities[base][quote] = _density;
  }

  function read(address base, address quote)
    external
    view
    override
    returns (uint, uint)
  {
    return (gasprice, densities[base][quote]);
  }

  function notifySuccess(DexCommon.SingleOrder calldata sor, address taker)
    external
    override
  {
    emit L.TradeSuccess(sor, taker);
  }

  function notifyFail(DexCommon.SingleOrder calldata sor) external override {
    emit L.TradeFail(sor);
  }
}
