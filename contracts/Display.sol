// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
import "./Dex.sol";
import "hardhat/console.sol";

library Display {
  /* ****************************************************************
   * Register/read address->name mappings to make logs easier to read.
   *****************************************************************/

  // Disgusting hack so a library can manipulate storage refs.
  bytes32 constant NAMES_POS = keccak256("Display.NAMES_POS");

  // Store mapping in library caller's storage.
  // That's quite fragile.
  struct Registers {
    mapping(address => string) map;
  }

  // Also send mapping to javascript test interpreter.  The interpreter COULD
  // just make an EVM call to map every name but that would probably be very
  // slow.  So we cache locally.
  event Register(address addr, string name);

  function registers() internal view returns (Registers storage) {
    Registers storage regs;
    bytes32 _slot = NAMES_POS;
    assembly {
      regs.slot := _slot
    }
    return regs;
  }

  function register(address addr, string memory name) internal {
    registers().map[addr] = name;
    emit Register(addr, name);
  }

  function name(address addr) internal view returns (string memory) {
    string memory s = registers().map[addr];
    if (keccak256(bytes(s)) != keccak256(bytes(""))) {
      return s;
    } else {
      return "<not found>";
    }
  }

  /* End of register/read section */

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
    internal
    pure
    returns (string memory)
  {
    return string(abi.encodePacked(a, b));
  }

  function append(
    string memory a,
    string memory b,
    string memory c
  ) internal pure returns (string memory) {
    return string(abi.encodePacked(a, b, c));
  }

  function wei2str(uint w) internal view returns (string memory eth) {
    uint i = 0;
    while (w % 10 == 0) {
      w = w / 10;
      i += 1;
    }
    return (append(uint2str(w), "e", uint2str(i)));
  }

  function logOrderBook(Dex dex) internal view {
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
      console.log("[order %d] %s/%s", orderId, wei2str(wants), wei2str(gives));
      console.log(
        "(%d gas, %d to finish, %d penalty)",
        gasWanted,
        minFinishGas,
        penaltyPerGas
      );
      console.log(name(makerAddr));
      orderId = nextId;
    }
    console.log("-----------------------");
  }
}
