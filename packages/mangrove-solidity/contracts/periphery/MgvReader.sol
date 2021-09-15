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

  // Returns the orderbook for the base/quote pair in packed form. First array is ids, second is offers (as bytes32), third is offerDetails (as bytes32). Array will be of size num_offers. Tail may be 0-filled if order book size is strictly smaller than num_offers.
  function packed_book(
    address base,
    address quote,
    uint num_offers
  )
    public
    view
    returns (
      uint[] memory,
      bytes32[] memory,
      bytes32[] memory
    )
  {
    uint[] memory offerIds = new uint[](num_offers);
    bytes32[] memory offers = new bytes32[](num_offers);
    bytes32[] memory offerDetails = new bytes32[](num_offers);

    uint currentId = MP.local_unpack_best(mgv.locals(base, quote));
    uint i = 0;

    while (currentId != 0 && i < num_offers) {
      offerIds[i] = currentId;
      offers[i] = mgv.offers(base, quote, currentId);
      offerDetails[i] = mgv.offerDetails(base, quote, currentId);
      currentId = MP.offer_unpack_next(offers[i]);
      i = i + 1;
    }

    return (offerIds, offers, offerDetails);
  }

  // Returns the orderbook for the base/quote pair in unpacked form. First array is ids, second is offers (as structs), third is offerDetails (as structs). Array will be of size num_offers. Tail may be 0-filled if order book size is strictly smaller than num_offers.
  function book(
    address base,
    address quote,
    uint num_offers
  )
    public
    view
    returns (
      uint[] memory,
      ML.Offer[] memory,
      ML.OfferDetail[] memory
    )
  {
    uint[] memory offerIds = new uint[](num_offers);
    ML.Offer[] memory offers = new ML.Offer[](num_offers);
    ML.OfferDetail[] memory offerDetails = new ML.OfferDetail[](num_offers);

    uint currentId = MP.local_unpack_best(mgv.locals(base, quote));
    uint i = 0;
    while (currentId != 0 && i < num_offers) {
      offerIds[i] = currentId;
      (offers[i], offerDetails[i]) = mgv.offerInfo(base, quote, currentId);
      currentId = offers[i].next;
      i = i + 1;
    }
    return (offerIds, offers, offerDetails);
  }
}
