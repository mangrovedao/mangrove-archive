// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";
import "../../Dex.sol";
import "../Agents/TestToken.sol";

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
    this; // silence warning about pure mutability
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

  function nameOf(address addr) internal view returns (string memory) {
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

  function append(
    string memory a,
    string memory b,
    string memory c,
    string memory d
  ) internal pure returns (string memory) {
    return string(abi.encodePacked(a, b, c, d));
  }

  function toEthUnits(uint w, string memory units)
    internal
    pure
    returns (string memory eth)
  {
    string memory suffix = append(" ", units);

    if (w == 0) {
      return (append("0", suffix));
    }
    uint i = 0;
    while (w % 10 == 0) {
      w = w / 10;
      i += 1;
    }
    if (i >= 18) {
      w = w * (10**(i - 18));
      return append(uint2str(w), suffix);
    } else {
      uint zeroBefore = 18 - i;
      string memory zeros = "";
      while (zeroBefore > 1) {
        zeros = append(zeros, "0");
        zeroBefore--;
      }
      return (append("0.", zeros, uint2str(w), suffix));
    }
  }

  event OBState(
    uint[] offerIds,
    uint[] wants,
    uint[] gives,
    address[] makerAddr,
    uint[] gasreqs
  );

  function logOfferBook(
    Dex dex,
    address base,
    address quote,
    uint size
  ) internal {
    uint offerId = dex.bests(base, quote);

    uint[] memory wants = new uint[](size);
    uint[] memory gives = new uint[](size);
    address[] memory makerAddr = new address[](size);
    uint[] memory offerIds = new uint[](size);
    uint[] memory gasreqs = new uint[](size);
    uint c = 0;
    while ((offerId != 0) && (c < size)) {
      (DC.Offer memory offer, DC.OfferDetail memory od) =
        dex.getOfferInfo(base, quote, offerId, true);
      wants[c] = offer.wants;
      gives[c] = offer.gives;
      makerAddr[c] = od.maker;
      offerIds[c] = offerId;
      gasreqs[c] = od.gasreq;
      offerId = offer.next;
      c++;
    }
    emit OBState(offerIds, wants, gives, makerAddr, gasreqs);
  }

  function printOfferBook(
    Dex dex,
    address base,
    address quote
  ) internal view {
    uint offerId = dex.bests(base, quote);
    TestToken req_tk = TestToken(quote);
    TestToken ofr_tk = TestToken(base);

    console.log("-----Best offer: %d-----", offerId);
    while (offerId != 0) {
      (
        ,
        /* bool exists */
        // silence warning about unused argument
        uint wants,
        uint gives,
        uint nextId, // silence warning about unused argument // silence warning about unused argument // silence warning about unused argument // silence warning about unused argument /* uint gasreq */ /* uint minFinishGas */
        ,
        ,
        ,

      ) =
        /* uint gasprice */
        /* address makerAddr */
        dex.getOfferInfo(base, quote, offerId);
      console.log(
        "[offer %d] %s/%s",
        offerId,
        toEthUnits(wants, req_tk.symbol()),
        toEthUnits(gives, ofr_tk.symbol())
      );
      // console.log(
      //   "(%d gas, %d to finish, %d penalty)",
      //   gasreq,
      //   minFinishGas,
      //   gasprice
      // );
      // console.log(name(makerAddr));
      offerId = nextId;
    }
    console.log("-----------------------");
  }
}
