pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

// SPDX-License-Identifier: MIT

/// MangroveOffer is the basic building block to implement a reactive offer that interfaces with the Mangrove
abstract contract Persistent is MangroveOffer {
  function __posthookSuccess__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
  {
    uint new_gives = MP.offer_unpack_gives(order.offer) - order.wants;
    uint new_wants = MP.offer_unpack_wants(order.offer) - order.gives;
    try
      this.updateOffer(
        order.outbound_tkn,
        order.inbound_tkn,
        new_wants,
        new_gives,
        MP.offerDetail_unpack_gasreq(order.offerDetail),
        MP.offer_unpack_gasprice(order.offer),
        MP.offer_unpack_next(order.offer),
        order.offerId
      )
    {} catch Error(string memory message) {
      emit PosthookFail(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        message
      );
    } catch {
      emit PosthookFail(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        "Unexpected reason"
      );
    }
  }

  function __autoRefill__(
    address outbound_tkn,
    address inbound_tkn,
    uint gasreq,
    uint gasprice,
    uint offerId
  ) internal virtual override returns (bool) {
    uint toAdd = getMissingProvision(
      outbound_tkn,
      inbound_tkn,
      gasreq,
      gasprice,
      offerId
    );
    if (toAdd > 0) {
      try MGV.fund{value: toAdd}() {
        return true;
      } catch {
        return false;
      }
    }
    return true;
  }
}
