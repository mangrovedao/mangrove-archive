// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import {DexCommon as DC} from "./DexCommon.sol";
import "./Dex.sol";

library DexIt {
  // Read a particular offer's information.
  function getOfferInfo(
    Dex dex,
    address base,
    address quote,
    uint offerId
  )
    external
    view
    returns (
      bool,
      DC.Offer memory,
      DC.OfferDetail memory
    )
  {
    bytes32 offer = dex.offers(base, quote, offerId);
    bool exists = dex.isLive(offer);
    DC.Offer memory offerStruct =
      DC.Offer({
        prev: $$(o_prev("offer")),
        next: $$(o_next("offer")),
        wants: $$(o_wants("offer")),
        gives: $$(o_gives("offer")),
        gasprice: $$(o_gasprice("offer"))
      });

    bytes32 offerDetail = dex.offerDetails(base, quote, offerId);

    DC.OfferDetail memory offerDetailStruct =
      DC.OfferDetail({
        maker: $$(od_maker("offerDetail")),
        gasreq: $$(od_gasreq("offerDetail")),
        gasbase: $$(od_gasbase("offerDetail"))
      });
    return (exists, offerStruct, offerDetailStruct);
  }

  /* Convenience function to get best offer of the given pair */
  function getBest(
    Dex dex,
    address base,
    address quote
  ) external view returns (uint) {
    bytes32 local = dex.locals(base, quote);
    return $$(loc_best("local"));
  }

  /* Convenience function to check whether given pair is locked */
  function isLocked(
    Dex dex,
    address base,
    address quote
  ) external view returns (bool) {
    bytes32 local = dex.locals(base, quote);
    return $$(loc_lock("local")) > 0;
  }
}
