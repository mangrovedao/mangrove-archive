pragma solidity ^0.7.0;
pragma abicoder v2;
// SPDX-License-Identifier: MIT

contract TradeHandler {
  enum Fail {
    None, // Trade was a success. NB: Do not move this field as it should be the default value
    Get, // Trade was dropped by maker due to a lack of liquidity
    Price, // Trade was dropped because of price slippage
    Receive, // Mangrove dropped failade when ERC20 (quote) rejected maker address as receiver
    Transfer, // Mangrove dropped failade when ERC20 (base) refused to failansfer funds from maker account to Mangrove
    Put // Unable to put liquidity
  }

  function failOfStatus(bytes32 statusCode) internal pure returns (Fail fail_switch) {
    if (statusCode == "mgv/makerTransferFail") {
      fail_switch = Fail.Transfer;
    } else {
      if (statusCode == "mgv/makerReceiveFail") {
        fail_switch = Fail.Receive;
      }
    }
  }

  function arity(Fail fail_switch) private pure returns (uint) {
    if (fail_switch == Fail.Get || fail_switch == Fail.Put) {
      return 1;
    }
    if (fail_switch == Fail.Price) {
      return 2;
    }
    else {
      return 0;
    }
  }

  function wordOfBytes(bytes memory data) private pure returns (bytes32 w) {
    assembly {
      w := mload(add(data, 32))
    }
  }
  function bytesOfWord(bytes32 w) private pure returns (bytes memory data) {
    data = new bytes(32);
    assembly {
      mstore(add(data, 32), w)
    }
  }
  function wordOfUint(uint x) private pure returns (bytes32 w) {
    w = bytes32(x);
  }

  function tradeRevertWithBytes(bytes memory data) private pure {
    assembly {
      revert(add(data, 32), 32)
    }
  }

  // failing a failade with either 1 or 2 arguments.
  function endTrade(bool drop, Fail fail_switch)
    internal
    pure
    returns (bytes32 w)
  {
    bytes memory data = abi.encodePacked(fail_switch);
    if (drop){
      tradeRevertWithBytes(data);
    }
    else {
      w = wordOfBytes(data);
    }
  }
  function endTrade(bool drop, Fail fail_switch, uint96 arg)
    internal
    pure
    returns (bytes32 w)
  {
    bytes memory data = abi.encodePacked(fail_switch, arg);
    if (drop){
      tradeRevertWithBytes(data);
    }
    else {
      w = wordOfBytes(data);
    }
  }
  function endTrade(bool drop, Fail fail_switch, uint96 arg0, uint96 arg1)
    internal
    pure
    returns (bytes32 w)
  {
    bytes memory data = abi.encodePacked(fail_switch, arg0,arg1);
    if (drop){
      tradeRevertWithBytes(data);
    }
    else {
      w = wordOfBytes(data);
    }
  }

  bytes32 constant MASKSWITCH =   0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  bytes32 constant MASKFIRSTARG = 0x00000000000000000000000000ffffffffffffffffffffffffffffffffffffff;

  function getMakerData(bytes32 w)
    internal
    pure
    returns (Fail fail_switch, uint[] memory args)
  {
    fail_switch = decodeSwitch(w);
    uint N = arity(fail_switch);
    args = new uint[](N);
    if (N > 0) {
      bytes32 arg0 = (w & MASKSWITCH) >> 19*8; // ([fail_switch:1])[arg0:12][arg1 + padding:19]
      args[0] = abi.decode(bytesOfWord(arg0),(uint96));
      if (N == 2) {
        bytes32 arg1 = (w & MASKFIRSTARG) >> 7*8; // ([fail_switch:1][arg0:12])[arg1:12][padding:7]
        args[1] = abi.decode(bytesOfWord(arg1),(uint96));
      }
    }
  }

  function decodeSwitch(bytes32 w) private pure returns (Fail fail_switch){
    bytes memory switch_data = bytesOfWord(w>>(31*8)); // Fail enum is encoded in the first byte
    fail_switch = abi.decode(switch_data,(Fail));
  }
}