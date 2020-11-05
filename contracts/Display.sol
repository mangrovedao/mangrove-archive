// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
import "./Dex.sol";
import "hardhat/console.sol";

library Display {
  function uint2str(uint _i)
    internal
    pure
    returns (string memory _uintAsString)
  {
    if (_i == 0) {
      return "0";
    }
    uint j = _i;
    uint len;
    while (j != 0) {
      len++;
      j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint k = len - 1;
    while (_i != 0) {
      bstr[k--] = byte(uint8(48 + (_i % 10)));
      _i /= 10;
    }
    return string(bstr);
  }

  function append(string memory a, string memory b)
    external
    pure
    returns (string memory)
  {
    return string(abi.encodePacked(a, b));
  }

  function logOrderBook(Dex dex) external view {
    uint orderId = dex.best();
    console.log("-----Best order: %d-----", dex.getBest());
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
    console.log("-----------------------");
  }
}
