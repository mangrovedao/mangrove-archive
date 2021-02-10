// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import {DexCommon as DC} from "./DexCommon.sol";
import "./Dex.sol";

library DexIt {
  // Read a particular offer's information.

  /* # Configuration */
  /* should not be called internally, would be a huge memory copying waste */
  function getConfig(
    Dex dex,
    address base,
    address quote
  ) external returns (DC.Config memory ret) {
    (bytes32 _global, bytes32 _local) = dex.getConfig(base, quote);
    ret.global = DC.Global({
      monitor: $$(glo_monitor("_global")),
      useOracle: $$(glo_useOracle("_global")) > 0,
      notify: $$(glo_notify("_global")) > 0,
      gasprice: $$(glo_gasprice("_global")),
      gasmax: $$(glo_gasmax("_global")),
      dead: $$(glo_dead("_global")) > 0
    });
    ret.local = DC.Local({
      active: $$(loc_active("_local")) > 0,
      gasbase: $$(loc_gasbase("_local")),
      fee: $$(loc_fee("_local")),
      density: $$(loc_density("_local")),
      best: $$(loc_best("_local")),
      lock: $$(loc_lock("_local")) > 0,
      lastId: $$(loc_lastId("_local"))
    });
  }

  function getOfferInfo(
    Dex dex,
    address base,
    address quote,
    uint offerId
  )
    internal
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
  ) internal view returns (uint) {
    bytes32 local = dex.locals(base, quote);
    return $$(loc_best("local"));
  }

  /* Convenience function to check whether given pair is locked */
  function isLocked(
    Dex dex,
    address base,
    address quote
  ) internal view returns (bool) {
    bytes32 local = dex.locals(base, quote);
    return $$(loc_lock("local")) > 0;
  }

  /*To be used to revert a makerTrade function with data to pass to posthook */
  function tradeRevert(bytes32 data) internal {
    bytes memory revData = new bytes(32);
    assembly {
      mstore(add(revData, 32), data)
      revert(add(revData, 32), 32)
    }
  }
}
