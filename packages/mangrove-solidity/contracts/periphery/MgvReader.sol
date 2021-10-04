// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;
import {MgvLib as ML} from "../MgvLib.sol";
import {MgvPack as MP} from "../MgvPack.sol";
import {Mangrove} from "../Mangrove.sol";

contract MgvReader {
  Mangrove immutable mgv;

  constructor(address _mgv) {
    mgv = Mangrove(payable(_mgv));
  }

  // Returns the orderbook for the outbound_tkn/inbound_tkn pair in packed form. First number is id of next offer (0 is we're done). First array is ids, second is offers (as bytes32), third is offerDetails (as bytes32). Array will be of size `maxOffers`. Tail may be 0-filled if order book size is strictly smaller than `maxOffers`.
  function packedBook(
    address outbound_tkn,
    address inbound_tkn,
    uint fromId,
    uint maxOffers
  )
    public
    view
    returns (
      uint,
      uint[] memory,
      bytes32[] memory,
      bytes32[] memory
    )
  {
    uint[] memory offerIds = new uint[](maxOffers);
    bytes32[] memory offers = new bytes32[](maxOffers);
    bytes32[] memory details = new bytes32[](maxOffers);

    uint currentId;
    if (fromId == 0) {
      currentId = MP.local_unpack_best(mgv.locals(outbound_tkn, inbound_tkn));
    } else {
      currentId = fromId;
    }

    uint i = 0;

    while (currentId != 0 && i < maxOffers) {
      offerIds[i] = currentId;
      offers[i] = mgv.offers(outbound_tkn, inbound_tkn, currentId);
      details[i] = mgv.offerDetails(outbound_tkn, inbound_tkn, currentId);
      currentId = MP.offer_unpack_next(offers[i]);
      i = i + 1;
    }

    assembly {
      mstore(offerIds, i)
      mstore(offers, i)
      mstore(details, i)
    }

    return (currentId, offerIds, offers, details);
  }

  // Returns the orderbook for the outbound_tkn/inbound_tkn pair in unpacked form. First number is id of next offer (0 if we're done). First array is ids, second is offers (as structs), third is offerDetails (as structs). Array will be of size `maxOffers`. Tail may be 0-filled if order book size is strictly smaller than `maxOffers`.
  function book(
    address outbound_tkn,
    address inbound_tkn,
    uint fromId,
    uint maxOffers
  )
    public
    view
    returns (
      uint,
      uint[] memory,
      ML.Offer[] memory,
      ML.OfferDetail[] memory
    )
  {
    uint[] memory offerIds = new uint[](maxOffers);
    ML.Offer[] memory offers = new ML.Offer[](maxOffers);
    ML.OfferDetail[] memory details = new ML.OfferDetail[](maxOffers);

    uint currentId;
    if (fromId == 0) {
      currentId = MP.local_unpack_best(mgv.locals(outbound_tkn, inbound_tkn));
    } else {
      currentId = fromId;
    }

    uint i = 0;
    while (currentId != 0 && i < maxOffers) {
      offerIds[i] = currentId;
      (offers[i], details[i]) = mgv.offerInfo(
        outbound_tkn,
        inbound_tkn,
        currentId
      );
      currentId = offers[i].next;
      i = i + 1;
    }

    assembly {
      mstore(offerIds, i)
      mstore(offers, i)
      mstore(details, i)
    }

    return (currentId, offerIds, offers, details);
  }
}
