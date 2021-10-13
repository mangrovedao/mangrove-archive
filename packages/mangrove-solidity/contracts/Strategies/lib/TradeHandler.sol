pragma solidity ^0.7.0;
pragma abicoder v2;
// SPDX-License-Identifier: MIT

import "../../MgvPack.sol";
import "../../Mangrove.sol";
import "../../MgvLib.sol";

//import "hardhat/console.sol";

contract TradeHandler {
  enum PostHook {
    Success, // Trade was a success. NB: Do not move this field as it should be the default value
    Get, // Trade was dropped by maker due to a lack of liquidity
    Reneged, // Trade was dropped because of price slippage
    Fallback // Fallback posthook
  }

  /// @notice extracts old offer from the order that is received from the Mangrove
  function unpackOfferFromOrder(MgvLib.SingleOrder calldata order)
    internal
    pure
    returns (
      uint offer_wants,
      uint offer_gives,
      uint gasreq,
      uint gasprice
    )
  {
    gasreq = MgvPack.offerDetail_unpack_gasreq(order.offerDetail);
    (, , offer_wants, offer_gives, gasprice) = MgvPack.offer_unpack(
      order.offer
    );
  }

  function getProvision(
    address base,
    address quote,
    Mangrove mgv,
    uint gasreq,
    uint gasprice
  ) internal returns (uint) {
    ML.Config memory config = mgv.config(base, quote);
    uint _gp;
    if (config.global.gasprice > gasprice) {
      _gp = uint(config.global.gasprice);
    } else {
      _gp = gasprice;
    }
    return ((gasreq +
      config.local.overhead_gasbase +
      config.local.offer_gasbase) *
      _gp *
      10**9);
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

  function wordOfUint(uint x) internal pure returns (bytes32 w) {
    w = bytes32(x);
  }

  function revertWithBytes(bytes memory data) private pure {
    assembly {
      revert(add(data, 32), 32)
    }
  }

  function returnData(bool drop, bytes memory message)
    internal
    pure
    returns (bytes32 w)
  {
    if (drop) {
      revertWithBytes(message);
    } else {
      w = wordOfBytes(message);
    }
  }

  function returnData(bool drop, bytes32 message)
    internal
    pure
    returns (bytes32 w)
  {
    bytes memory data = bytesOfWord(message);
    if (drop) {
      revertWithBytes(data);
    } else {
      w = wordOfBytes(data);
    }
  }

  function returnData(bool drop, PostHook postHook_switch)
    internal
    pure
    returns (bytes32 w)
  {
    bytes memory data = abi.encodePacked(postHook_switch);
    if (drop) {
      revertWithBytes(data);
    } else {
      w = wordOfBytes(data);
    }
  }

  function returnData(
    bool drop,
    PostHook postHook_switch,
    bytes32 message
  ) internal pure returns (bytes32 w) {
    bytes memory data = abi.encodePacked(postHook_switch, message);
    if (drop) {
      revertWithBytes(data);
    } else {
      w = wordOfBytes(data);
    }
  }

  function getMakerData(bytes32 w)
    internal
    view
    returns (PostHook postHook_switch, bytes32 message)
  {
    postHook_switch = decodeSwitch(w);
    message = (w << 1) >> 1; // ([postHook_switch:1])[message:31]
  }

  function decodeSwitch(bytes32 w)
    private
    pure
    returns (PostHook postHook_switch)
  {
    bytes memory switch_data = bytesOfWord(w >> (31 * 8)); // PostHook enum is encoded in the first byte
    postHook_switch = abi.decode(switch_data, (PostHook));
  }
}
