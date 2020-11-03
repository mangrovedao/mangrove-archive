// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.1;

enum ConfigKey {
  admin,
  takerFee,
  minFinishGas,
  dustPerGasWanted,
  minGasWanted,
  penaltyPerGas,
  transferGas,
  maxGasWanted
}

struct Config {
  address admin;
  uint takerFee; // in basis points
  uint minFinishGas; // (24) min gas available
  uint dustPerGasWanted; // (32) min amount to offer per gas requested, in OFR_TOKEN;
  uint minGasWanted; // (32) minimal amount of gas you can ask for; also used for market order's dust estimation
  uint penaltyPerGas; // (48) in wei;
  uint transferGas; //default amount of gas given for a transfer
  uint maxGasWanted; //max amount of gas required by an order
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

function isOrder(Order memory order) pure returns (bool) {
  return order.gives > 0;
}

library DexEvents {
  // Emitted when receiver withdraws amount from Dex
  event Transfer(address payable receiver, uint amout);

  // Emitted when Dex receives amount from sender
  event Receive(address sender, uint amount);

  // Events that are emitted upon a Dex reconfiguration
  event SetTakerFee(uint value);
  event SetMinFinishGas(uint value);
  event SetDustPerGasWanted(uint value);
  event SetminGasWanted(uint value);
  event SetPenaltyPerGas(uint value);
  event SetTransferGas(uint value);

  // Dex interactions

  // Emitted upon Dex closure
  event CloseMarket();

  // Emitted if orderId was successfully cancelled.
  // No event is emitted if orderId is absent from order book
  event CancelOrder(uint orderId);

  // Emitted if a new order was inserted into order book
  // maker is the address of the Maker contract that implements the order
  event NewOrder(
    address maker,
    uint96 wants,
    uint96 gives,
    uint24 gasWanted,
    uint orderId
  );

  // Emitted when orderId is removed from Order Book.
  event DeleteOrder(uint orderId);
}
