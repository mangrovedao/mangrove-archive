pragma solidity ^0.7.0;
pragma abicoder v2;

// SPDX-License-Identifier: MIT

contract TradeHandler {
  enum Fail {
    None, // Trade was a success. NB: Do not move this field as it should be the default value
    Liquidity, // Trade was dropped by maker due to a lack of liquidity
    Slippage, // Trade was dropped because of price slippage
    Receive, // Mangrove dropped failade when ERC20 (quote) rejected maker address as receiver
    Transfer, // Mangrove dropped failade when ERC20 (base) refused to failansfer funds from maker account to Mangrove
    Put // Unable to put liquidity
  }

  function arity(Fail fail) private pure returns (uint) {
    if (fail == Fail.None || fail == Fail.Receive || fail == Fail.Transfer) {
      return 0;
    }
    if (fail == Fail.Liquidity || fail == Fail.Put) {
      return 1;
    }
    if (fail == Fail.Slippage) {
      return 2;
    }
  }

  function wordOfBytes(bytes memory data) internal pure returns (bytes32 w) {
    assembly {
      w := mload(add(data, 32))
    }
  }

  function bytesOfWord(bytes32 w) internal pure returns (bytes memory data) {
    data = new bytes(32);
    assembly {
      mstore(add(data, 32), w)
    }
  }

  function tradeRevertWithWord(bytes32 w) internal pure {
    bytes memory data = bytesOfWord(w);
    assembly {
      revert(add(data, 32), 32)
    }
  }

  function tradeRevertWithBytes(bytes memory data) internal pure {
    assembly {
      revert(add(data, 32), 32)
    }
  }

  // failing a failade with either 1 or 2 arguments.
  function endTrade(Fail failtype, uint96[] memory args)
    internal
    pure
    returns (bytes32 w)
  {
    if (failtype == Fail.None) {
      w = wordOfBytes(abi.encode(failtype, ""));
    }
    bytes memory fail_data = new bytes(32);
    fail_data = abi.encode(failtype, abi.encode(args));
    tradeRevertWithBytes(fail_data);
  }

  function getMakerData(bytes32 w)
    internal
    pure
    returns (Fail failtype, uint[] memory args)
  {
    bytes memory data = bytesOfWord(w);
    bytes memory continuation_data;
    (failtype, continuation_data) = abi.decode(data, (Fail, bytes));

    if (failtype == Fail.Liquidity) {
      args = new uint[](1);
      args[0] = abi.decode(continuation_data, (uint96));
    } else {
      // failtype == Fail.Slippage
      args = new uint[](2);
      (uint arg0, uint arg1) = abi.decode(continuation_data, (uint96, uint96));
      args[0] = uint(arg0);
      args[1] = uint(arg1);
    }
  }
}
