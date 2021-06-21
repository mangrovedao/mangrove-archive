// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;
import {MgvCommon as MC, MgvEvents, IMgvMonitor} from "./MgvCommon.sol";
import {MgvRoot} from "./MgvRoot.sol";

contract MgvHasOffers is MgvRoot {
  /* Given a `base`,`quote` pair, the mappings `offers` and `offerDetails` associate two 256 bits words to each offer id. Those words encode information detailed in `structs.js`.

     The mapping are `base => quote => offerId => bytes32`.
   */
  mapping(address => mapping(address => mapping(uint => bytes32)))
    public offers;
  mapping(address => mapping(address => mapping(uint => bytes32)))
    public offerDetails;

  /* Makers provision their possible penalties in the `balanceOf` mapping.

       Offers specify the amount of gas they require for successful execution (`gasreq`). To minimize book spamming, market makers must provision a *penalty*, which depends on their `gasreq` and on the pair's `*_gasbase`. This provision is deducted from their `balanceOf`. If an offer fails, part of that provision is given to the taker, as retribution. The exact amount depends on the gas used by the offer before failing.

       The Mangrove keeps track of their available balance in the `balanceOf` map, which is decremented every time a maker creates a new offer, and may be modified on offer updates/cancelations/takings.
     */
  mapping(address => uint) public balanceOf;

  /* Convenience function to get best offer of the given pair */
  function best(address base, address quote) external view returns (uint) {
    bytes32 local = locals[base][quote];
    return $$(local_best("local"));
  }

  /* Returns information about an offer in ABI-compatible structs. Do not use internally, would be a huge memory-copying waste. Use `offers[base][quote]` and `offerDetails[base][quote]` instead. */
  function offerInfo(
    address base,
    address quote,
    uint offerId
  ) external view returns (MC.Offer memory, MC.OfferDetail memory) {
    bytes32 offer = offers[base][quote][offerId];
    MC.Offer memory offerStruct =
      MC.Offer({
        prev: $$(offer_prev("offer")),
        next: $$(offer_next("offer")),
        wants: $$(offer_wants("offer")),
        gives: $$(offer_gives("offer")),
        gasprice: $$(offer_gasprice("offer"))
      });

    bytes32 offerDetail = offerDetails[base][quote][offerId];

    MC.OfferDetail memory offerDetailStruct =
      MC.OfferDetail({
        maker: $$(offerDetail_maker("offerDetail")),
        gasreq: $$(offerDetail_gasreq("offerDetail")),
        overhead_gasbase: $$(offerDetail_overhead_gasbase("offerDetail")),
        offer_gasbase: $$(offerDetail_offer_gasbase("offerDetail"))
      });
    return (offerStruct, offerDetailStruct);
  }

  /* # Provision debit/credit utility functions */
  /* `balanceOf` is in wei of ETH. */

  function debitWei(address maker, uint amount) internal {
    uint makerBalance = balanceOf[maker];
    require(makerBalance >= amount, "mgv/insufficientProvision");
    balanceOf[maker] = makerBalance - amount;
    emit MgvEvents.Debit(maker, amount);
  }

  function creditWei(address maker, uint amount) internal {
    balanceOf[maker] += amount;
    emit MgvEvents.Credit(maker, amount);
  }

  /* # Low-level offer deletion */

  /* When an offer is deleted, it is marked as such by setting `gives` to 0. Note that provision accounting in the Mangrove aims to minimize writes. Each maker `fund`s the Mangrove to increase its balance. When an offer is created/updated, we compute how much should be reserved to pay for possible penalties. That amount can always be recomputed with `offer.gasprice * (offerDetail.gasreq + offerDetail.overhead_gasbase + offerDetail.offer_gasbase)`. The balance is updated to reflect the remaining available ethers.

     Now, when an offer is deleted, the offer can stay provisioned, or be `deprovision`ed. In the latter case, we set `gasprice` to 0, which induces a provision of 0. */
  function dirtyDeleteOffer(
    address base,
    address quote,
    uint offerId,
    bytes32 offer,
    bool deprovision
  ) internal {
    offer = $$(set_offer("offer", [["gives", 0]]));
    if (deprovision) {
      offer = $$(set_offer("offer", [["gasprice", 0]]));
    }
    offers[base][quote][offerId] = offer;
  }

  /* # Misc. low-level functions */

  /* Connect the predecessor and sucessor of `id` through their `next`/`prev` pointers. For more on the book structure, see `MangroveCommon.sol`. This step is not necessary during a market order, so we only call `dirtyDeleteOffer`.

  **Warning**: calling with `worseId = 0` will set `betterId` as the best. So with `worseId = 0` and `betterId = 0`, it sets the book to empty and loses track of existing offers.

  **Warning**: may make memory copy of `local.best` stale. Returns new `local`. */
  function stitchOffers(
    address base,
    address quote,
    uint worseId,
    uint betterId,
    bytes32 local
  ) internal returns (bytes32) {
    if (worseId != 0) {
      offers[base][quote][worseId] = $$(
        set_offer("offers[base][quote][worseId]", [["next", "betterId"]])
      );
    } else {
      local = $$(set_local("local", [["best", "betterId"]]));
    }

    if (betterId != 0) {
      offers[base][quote][betterId] = $$(
        set_offer("offers[base][quote][betterId]", [["prev", "worseId"]])
      );
    }

    return local;
  }

  /* Check whether an offer is 'live', that is: inserted in the order book. The Mangrove holds a `base => quote => id => bytes32` mapping in storage. Offer ids that are not yet assigned or that point to since-deleted offer will point to the null word. A common way to check for initialization is to add an `exists` field to a struct. In our case, liveness can be denoted by `offer.gives > 0`. So we just check the `gives` field. */
  function isLive(bytes32 offer) public pure returns (bool) {
    return $$(offer_gives("offer")) > 0;
  }
}
