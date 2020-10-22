// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.1;

library DC {
  enum ConfigKey {
    admin,
    takerFee,
    minFinishGas,
    dustPerGasWanted,
    minGasWanted,
    penaltyPerGas,
    transferGas
  }

  struct Config {
    address admin;
    uint takerFee; // in basis points
    uint minFinishGas; // (24) min gas available
    uint dustPerGasWanted; // (32) min amount to offer per gas requested, in OFR_TOKEN;
    uint minGasWanted; // (32) minimal amount of gas you can ask for; also used for market order's dust estimation
    uint penaltyPerGas; // (48) in wei;
    uint transferGas; //default amount of gas given for a transfer
  }

  struct Order {
    uint32 prev; // better orderm
    uint32 next; // worse order
    uint96 wants; // amount requested in OFR_TOKEN
    uint96 gives; // amount on order in REQ_TOKEN
  }

  struct OrderDetail {
    uint24 gasWanted; // gas requested
    uint24 minFinishGas; // global minFinishGas at order creation time
    uint48 penaltyPerGas; // global penaltyPerGas at order creation time
    address maker;
  }

  struct UintContainer {
    uint value;
  }

  function isOrder(Order memory order) internal pure returns (bool) {
    return order.gives > 0;
  }
}
