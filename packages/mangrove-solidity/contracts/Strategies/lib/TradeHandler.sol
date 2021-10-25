pragma solidity ^0.7.0;
pragma abicoder v2;
// SPDX-License-Identifier: MIT

import {MgvPack as MP} from "../../MgvPack.sol";
import "../../Mangrove.sol";
import "../../MgvLib.sol";

//import "hardhat/console.sol";

contract TradeHandler {
  // bytes32 messages that signify success to Mangrove
  bytes32 constant PROCEED = ""; // successful exec

  // internal bytes32 to select appropriate posthook
  bytes32 constant RENEGED = "mgvOffer/reneged";
  bytes32 constant OUTOFLIQUIDITY = "mgvOffer/outOfLiquidity";

  // to wrap potentially reverting calls to mangrove
  event MangroveRevert(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint offerId,
    string message
  );

  event NotEnoughLiquidity(address token, uint amountMissing);

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
    gasreq = MP.offerDetail_unpack_gasreq(order.offerDetail);
    (, , offer_wants, offer_gives, gasprice) = MP.offer_unpack(order.offer);
  }

  function getProvision(
    Mangrove mgv,
    address base,
    address quote,
    uint gasreq,
    uint gasprice
  ) internal returns (uint) {
    (bytes32 globalData, bytes32 localData) = mgv.config(base, quote);
    uint _gp;
    if (MP.global_unpack_gasprice(globalData) > gasprice) {
      _gp = MP.global_unpack_gasprice(globalData);
    } else {
      _gp = gasprice;
    }
    return ((gasreq +
      MP.local_unpack_overhead_gasbase(localData) +
      MP.local_unpack_offer_gasbase(localData)) *
      _gp *
      10**9);
  }

  //queries the mangrove to get current gasprice (considered to compute bounty)
  function getCurrentGasPrice(Mangrove mgv) internal view returns (uint) {
    (bytes32 global_pack, ) = mgv.config(address(0), address(0));
    return MP.global_unpack_gasprice(global_pack);
  }

  //truncate some bytes into a byte32 word
  function returnTruncatedBytes(bytes memory data)
    internal
    pure
    returns (bytes32 w)
  {
    assembly {
      w := mload(add(data, 32))
    }
  }

  function returnUint(uint x) internal pure returns (bytes32 w) {
    w = bytes32(x);
  }
}
