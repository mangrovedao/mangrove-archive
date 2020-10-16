// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
import "./Dex.sol";
import "@nomiclabs/buidler/console.sol";

contract Display {
  function logOrderBook(Dex dex) internal view {
    uint orderId = dex.best();
    bool best = true;
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
      console.logAddress(makerAddr);
      //      console.log("%c Essai",'background: #222; color: #bada55');
      console.log("[order %d] %d/%d", orderId, wants, gives);
      console.log("(%d gas)", gasWanted);
      orderId = nextId;
      best = false;
    }
    console.log("----------");
  }
}
