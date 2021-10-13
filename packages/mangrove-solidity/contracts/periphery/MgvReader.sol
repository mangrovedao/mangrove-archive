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

  function offersEndpoints(
    address outbound_tkn,
    address inbound_tkn,
    uint fromId,
    uint maxOffers
  ) public view returns (uint, uint) {
    uint startId;

    if (fromId == 0) {
      startId = mgv.best(outbound_tkn, inbound_tkn);
    } else {
      startId = MP.offer_unpack_gives(
        mgv.offers(outbound_tkn, inbound_tkn, fromId)
      ) > 0
        ? fromId
        : 0;
    }

    uint currentId = startId;

    uint i = 0;

    while (currentId != 0 && i < maxOffers) {
      currentId = MP.offer_unpack_next(
        mgv.offers(outbound_tkn, inbound_tkn, currentId)
      );
      i = i + 1;
    }

    return (startId, i);
  }

  // Returns the orderbook for the outbound_tkn/inbound_tkn pair in packed form. First number is id of next offer (0 is we're done). First array is ids, second is offers (as bytes32), third is offerDetails (as bytes32). Array will be of size `min(# of offers in out/in list, maxOffers)`.
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
    (uint currentId, uint length) = offersEndpoints(
      outbound_tkn,
      inbound_tkn,
      fromId,
      maxOffers
    );

    uint[] memory offerIds = new uint[](length);
    bytes32[] memory offers = new bytes32[](length);
    bytes32[] memory details = new bytes32[](length);

    uint i = 0;

    while (currentId != 0 && i < length) {
      offerIds[i] = currentId;
      offers[i] = mgv.offers(outbound_tkn, inbound_tkn, currentId);
      details[i] = mgv.offerDetails(outbound_tkn, inbound_tkn, currentId);
      currentId = MP.offer_unpack_next(offers[i]);
      i = i + 1;
    }

    return (currentId, offerIds, offers, details);
  }

  // Returns the orderbook for the outbound_tkn/inbound_tkn pair in unpacked form. First number is id of next offer (0 if we're done). First array is ids, second is offers (as structs), third is offerDetails (as structs). Array will be of size `min(# of offers in out/in list, maxOffers)`.
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
    (uint currentId, uint length) = offersEndpoints(
      outbound_tkn,
      inbound_tkn,
      fromId,
      maxOffers
    );

    uint[] memory offerIds = new uint[](length);
    ML.Offer[] memory offers = new ML.Offer[](length);
    ML.OfferDetail[] memory details = new ML.OfferDetail[](length);

    uint i = 0;
    while (currentId != 0 && i < length) {
      offerIds[i] = currentId;
      (offers[i], details[i]) = mgv.offerInfo(
        outbound_tkn,
        inbound_tkn,
        currentId
      );
      currentId = offers[i].next;
      i = i + 1;
    }

    return (currentId, offerIds, offers, details);
  }

  function getProvision(
    address outbound_tkn,
    address inbound_tkn,
    uint ofr_gasreq,
    uint ofr_gasprice
  ) external view returns (uint) {
    (bytes32 global, bytes32 local) = mgv._config(outbound_tkn, inbound_tkn);
    uint _gp;
    uint global_gasprice = MP.global_unpack_gasprice(global);
    if (global_gasprice > ofr_gasprice) {
      _gp = global_gasprice;
    } else {
      _gp = ofr_gasprice;
    }
    return
      (ofr_gasreq +
        MP.local_unpack_overhead_gasbase(local) +
        MP.local_unpack_offer_gasbase(local)) *
      _gp *
      10**9;
  }
}
