// SPDX-License-Identifier:	AGPL-3.0

// MgvHasOffers.sol

// Copyright (C) 2021 Giry SAS.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity ^0.8.10;
pragma abicoder v2;
import {MgvLib as ML, HasMgvEvents, IMgvMonitor} from "./MgvLib.sol";
import {MgvRoot} from "./MgvRoot.sol";

/* `MgvHasOffers` contains the state variables and functions common to both market-maker operations and market-taker operations. Mostly: storing offers, removing them, updating market makers' provisions. */
contract MgvHasOffers is MgvRoot {
  /* # State variables */
  /* Given a `outbound_tkn`,`inbound_tkn` pair, the mappings `offers` and `offerDetails` associate two 256 bits words to each offer id. Those words encode information detailed in [`structs.js`](#structs.js).

     The mappings are `outbound_tkn => inbound_tkn => offerId => bytes32`.
   */
  mapping(address => mapping(address => mapping(uint => bytes32)))
    public offers;
  mapping(address => mapping(address => mapping(uint => bytes32)))
    public offerDetails;

  /* Makers provision their possible penalties in the `balanceOf` mapping.

       Offers specify the amount of gas they require for successful execution ([`gasreq`](#structs.js/gasreq)). To minimize book spamming, market makers must provision a *penalty*, which depends on their `gasreq` and on the pair's [`*_gasbase`](#structs.js/gasbase). This provision is deducted from their `balanceOf`. If an offer fails, part of that provision is given to the taker, as retribution. The exact amount depends on the gas used by the offer before failing.

       The Mangrove keeps track of their available balance in the `balanceOf` map, which is decremented every time a maker creates a new offer, and may be modified on offer updates/cancelations/takings.
     */
  mapping(address => uint) public balanceOf;

  /* # Read functions */
  /* Convenience function to get best offer of the given pair */
  function best(address outbound_tkn, address inbound_tkn)
    external
    view
    returns (uint)
  { unchecked {
    bytes32 local = locals[outbound_tkn][inbound_tkn];
    return $$(local_best("local"));
  }}

  /* Returns information about an offer in ABI-compatible structs. Do not use internally, would be a huge memory-copying waste. Use `offers[outbound_tkn][inbound_tkn]` and `offerDetails[outbound_tkn][inbound_tkn]` instead. */
  function offerInfo(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId
  ) external view returns (ML.OfferStruct memory, ML.OfferDetail memory) { unchecked {
    bytes32 offer = offers[outbound_tkn][inbound_tkn][offerId];
    ML.Offer memory offerStruct = ML.Offer({
      prev: $$(offer_prev("offer")),
      next: $$(offer_next("offer")),
      wants: $$(offer_wants("offer")),
      gives: $$(offer_gives("offer"))
    });

    bytes32 offerDetail = offerDetails[outbound_tkn][inbound_tkn][offerId];

    ML.OfferDetail memory offerDetailStruct = ML.OfferDetail({
      maker: $$(offerDetail_maker("offerDetail")),
      gasreq: $$(offerDetail_gasreq("offerDetail")),
      overhead_gasbase: $$(offerDetail_overhead_gasbase("offerDetail")),
      offer_gasbase: $$(offerDetail_offer_gasbase("offerDetail")),
      gasprice: $$(offerDetail_gasprice("offerDetail"))
    });
    return (offerStruct, offerDetailStruct);
  }}

  /* # Provision debit/credit utility functions */
  /* `balanceOf` is in wei of ETH. */

  function debitWei(address maker, uint amount) internal { unchecked {
    uint makerBalance = balanceOf[maker];
    require(makerBalance >= amount, "mgv/insufficientProvision");
    balanceOf[maker] = makerBalance - amount;
    emit Debit(maker, amount);
  }}

  function creditWei(address maker, uint amount) internal { unchecked {
    balanceOf[maker] += amount;
    emit Credit(maker, amount);
  }}

  /* # Misc. low-level functions */
  /* ## Offer deletion */

  /* When an offer is deleted, it is marked as such by setting `gives` to 0. Note that provision accounting in the Mangrove aims to minimize writes. Each maker `fund`s the Mangrove to increase its balance. When an offer is created/updated, we compute how much should be reserved to pay for possible penalties. That amount can always be recomputed with `offerDetail.gasprice * (offerDetail.gasreq + offerDetail.overhead_gasbase + offerDetail.offer_gasbase)`. The balance is updated to reflect the remaining available ethers.

     Now, when an offer is deleted, the offer can stay provisioned, or be `deprovision`ed. In the latter case, we set `gasprice` to 0, which induces a provision of 0. All code calling `dirtyDeleteOffer` with `deprovision` set to `true` must be careful to correctly account for where that provision is going (back to the maker's `balanceOf`, or sent to a taker as compensation). */
  function dirtyDeleteOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId,
    bytes32 offer,
    bytes32 offerDetail,
    bool deprovision
  ) internal { unchecked {
    offer = $$(set_offer("offer", [["gives", 0]]));
    if (deprovision) {
      offerDetail = $$(set_offerDetail("offerDetail", [["gasprice", 0]]));
    }
    offers[outbound_tkn][inbound_tkn][offerId] = offer;
    offerDetails[outbound_tkn][inbound_tkn][offerId] = offerDetail;
  }}

  /* ## Stitching the orderbook */

  /* Connect the offers `betterId` and `worseId` through their `next`/`prev` pointers. For more on the book structure, see [`structs.js`](#structs.js). Used after executing an offer (or a segment of offers), after removing an offer, or moving an offer.

  **Warning**: calling with `betterId = 0` will set `worseId` as the best. So with `betterId = 0` and `worseId = 0`, it sets the book to empty and loses track of existing offers.

  **Warning**: may make memory copy of `local.best` stale. Returns new `local`. */
  function stitchOffers(
    address outbound_tkn,
    address inbound_tkn,
    uint betterId,
    uint worseId,
    bytes32 local
  ) internal returns (bytes32) { unchecked {
    if (betterId != 0) {
      offers[outbound_tkn][inbound_tkn][betterId] = $$(
        set_offer(
          "offers[outbound_tkn][inbound_tkn][betterId]",
          [["next", "worseId"]]
        )
      );
    } else {
      local = $$(set_local("local", [["best", "worseId"]]));
    }

    if (worseId != 0) {
      offers[outbound_tkn][inbound_tkn][worseId] = $$(
        set_offer(
          "offers[outbound_tkn][inbound_tkn][worseId]",
          [["prev", "betterId"]]
        )
      );
    }

    return local;
  }}

  /* ## Check offer is live */
  /* Check whether an offer is 'live', that is: inserted in the order book. The Mangrove holds a `outbound_tkn => inbound_tkn => id => bytes32` mapping in storage. Offer ids that are not yet assigned or that point to since-deleted offer will point to an offer with `gives` field at 0. */
  function isLive(bytes32 offer) public pure returns (bool) { unchecked {
    return $$(offer_gives("offer")) > 0;
  }
}
