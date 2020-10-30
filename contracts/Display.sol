// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
import "./Dex.sol";
import "hardhat/console.sol";

contract Display {
  function logOrderBook(Dex dex) internal view {
    uint orderId = dex.best();
    console.log("----------");
    while (orderId != 0) {
      (
        uint wants,
        uint gives,
        uint nextId,
        uint gasWanted,
        uint minFinishGas,
        uint penaltyPerGas,
        address makerAddr
      ) = dex.getOrderInfo(orderId);
      console.log(
        "[order %d] %d/%d",
        orderId,
        wants / 0.01 ether,
        gives / 0.01 ether
      );
      console.log(
        "(%d gas, %d to finish, %d penalty)",
        gasWanted,
        minFinishGas,
        penaltyPerGas
      );
      console.logAddress(makerAddr);
      orderId = nextId;
    }
    console.log("----------");
  }
}
