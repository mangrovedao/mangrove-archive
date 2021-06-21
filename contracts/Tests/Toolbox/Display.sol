// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import "hardhat/console.sol";
import "../../AbstractMangrove.sol";
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

  event ERC20Balances(ERC20BL[] tokens, address[] accounts, uint[] balances);

  function logBalances(ERC20BL t1, address a1) internal {
    ERC20BL[] memory tokens = new ERC20BL[](1);
    tokens[0] = t1;
    address[] memory accounts = new address[](1);
    accounts[0] = a1;
    logBalances(tokens, accounts);
  }

  function logBalances(
    ERC20BL t1,
    address a1,
    address a2
  ) internal {
    ERC20BL[] memory tokens = new ERC20BL[](1);
    tokens[0] = t1;
    address[] memory accounts = new address[](2);
    accounts[0] = a1;
    accounts[1] = a2;
    logBalances(tokens, accounts);
  }

  function logBalances(
    ERC20BL t1,
    address a1,
    address a2,
    address a3
  ) internal {
    ERC20BL[] memory tokens = new ERC20BL[](1);
    tokens[0] = t1;
    address[] memory accounts = new address[](3);
    accounts[0] = a1;
    accounts[1] = a2;
    accounts[2] = a3;
    logBalances(tokens, accounts);
  }

  function logBalances(
    ERC20BL t1,
    ERC20BL t2,
    address a1
  ) internal {
    ERC20BL[] memory tokens = new ERC20BL[](2);
    tokens[0] = t1;
    tokens[1] = t2;
    address[] memory accounts = new address[](1);
    accounts[0] = a1;
    logBalances(tokens, accounts);
  }

  function logBalances(
    ERC20BL t1,
    ERC20BL t2,
    address a1,
    address a2
  ) internal {
    ERC20BL[] memory tokens = new ERC20BL[](2);
    tokens[0] = t1;
    tokens[1] = t2;
    address[] memory accounts = new address[](2);
    accounts[0] = a1;
    accounts[1] = a2;
    logBalances(tokens, accounts);
  }

  function logBalances(
    ERC20BL t1,
    ERC20BL t2,
    address a1,
    address a2,
    address a3
  ) internal {
    ERC20BL[] memory tokens = new ERC20BL[](2);
    tokens[0] = t1;
    tokens[1] = t2;
    address[] memory accounts = new address[](3);
    accounts[0] = a1;
    accounts[1] = a2;
    accounts[2] = a3;
    logBalances(tokens, accounts);
  }

  /* takes [t1,...,tM], [a1,...,aN]
       logs also [...b(t1,aj) ... b(tM,aj) ...] */

  function logBalances(ERC20BL[] memory tokens, address[] memory accounts)
    internal
  {
    uint[] memory balances = new uint[](tokens.length * accounts.length);
    for (uint i = 0; i < tokens.length; i++) {
      for (uint j = 0; j < accounts.length; j++) {
        uint bal = tokens[i].balanceOf(accounts[j]);
        balances[i * accounts.length + j] = bal;
        //console.log(tokens[i].symbol(),nameOf(accounts[j]),bal);
      }
    }
    emit ERC20Balances(tokens, accounts, balances);
  }

  /* 1 arg logging (string/uint) */

  event LogString(string a);

  function log(string memory a) internal {
    emit LogString(a);
  }

  event LogUint(uint a);

  function log(uint a) internal {
    emit LogUint(a);
  }

  /* 2 arg logging (string/uint) */

  event LogStringString(string a, string b);

  function log(string memory a, string memory b) internal {
    emit LogStringString(a, b);
  }

  event LogStringUint(string a, uint b);

  function log(string memory a, uint b) internal {
    emit LogStringUint(a, b);
  }

  event LogUintUint(uint a, uint b);

  function log(uint a, uint b) internal {
    emit LogUintUint(a, b);
  }

  event LogUintString(uint a, string b);

  function log(uint a, string memory b) internal {
    emit LogUintString(a, b);
  }

  /* 3 arg logging (string/uint) */

  event LogStringStringString(string a, string b, string c);

  function log(
    string memory a,
    string memory b,
    string memory c
  ) internal {
    emit LogStringStringString(a, b, c);
  }

  event LogStringStringUint(string a, string b, uint c);

  function log(
    string memory a,
    string memory b,
    uint c
  ) internal {
    emit LogStringStringUint(a, b, c);
  }

  event LogStringUintUint(string a, uint b, uint c);

  function log(
    string memory a,
    uint b,
    uint c
  ) internal {
    emit LogStringUintUint(a, b, c);
  }

  event LogStringUintString(string a, uint b, string c);

  function log(
    string memory a,
    uint b,
    string memory c
  ) internal {
    emit LogStringUintString(a, b, c);
  }

  event LogUintUintUint(uint a, uint b, uint c);

  function log(
    uint a,
    uint b,
    uint c
  ) internal {
    emit LogUintUintUint(a, b, c);
  }

  event LogUintStringUint(uint a, string b, uint c);

  function log(
    uint a,
    string memory b,
    uint c
  ) internal {
    emit LogUintStringUint(a, b, c);
  }

  event LogUintStringString(uint a, string b, string c);

  function log(
    uint a,
    string memory b,
    string memory c
  ) internal {
    emit LogUintStringString(a, b, c);
  }

  event OBState(
    address base,
    address quote,
    uint[] offerIds,
    uint[] wants,
    uint[] gives,
    address[] makerAddr,
    uint[] gasreqs
  );

  function logOfferBook(
    AbstractMangrove mgv,
    address base,
    address quote,
    uint size
  ) internal {
    uint offerId = mgv.best(base, quote);

    uint[] memory wants = new uint[](size);
    uint[] memory gives = new uint[](size);
    address[] memory makerAddr = new address[](size);
    uint[] memory offerIds = new uint[](size);
    uint[] memory gasreqs = new uint[](size);
    uint c = 0;
    while ((offerId != 0) && (c < size)) {
      (ML.Offer memory offer, ML.OfferDetail memory od) =
        mgv.offerInfo(base, quote, offerId);
      wants[c] = offer.wants;
      gives[c] = offer.gives;
      makerAddr[c] = od.maker;
      offerIds[c] = offerId;
      gasreqs[c] = od.gasreq;
      offerId = offer.next;
      c++;
    }
    emit OBState(base, quote, offerIds, wants, gives, makerAddr, gasreqs);
  }

  function printOfferBook(
    AbstractMangrove mgv,
    address base,
    address quote
  ) internal view {
    uint offerId = mgv.best(base, quote);
    TestToken req_tk = TestToken(quote);
    TestToken ofr_tk = TestToken(base);

    console.log("-----Best offer: %d-----", offerId);
    while (offerId != 0) {
      (ML.Offer memory ofr, ) = mgv.offerInfo(base, quote, offerId);
      console.log(
        "[offer %d] %s/%s",
        offerId,
        toEthUnits(ofr.wants, req_tk.symbol()),
        toEthUnits(ofr.gives, ofr_tk.symbol())
      );
      // console.log(
      //   "(%d gas, %d to finish, %d penalty)",
      //   gasreq,
      //   minFinishGas,
      //   gasprice
      // );
      // console.log(name(makerAddr));
      offerId = ofr.next;
    }
    console.log("-----------------------");
  }
}
