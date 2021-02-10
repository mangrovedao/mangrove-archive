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
      monitor: $$(global_monitor("_global")),
      useOracle: $$(global_useOracle("_global")) > 0,
      notify: $$(global_notify("_global")) > 0,
      gasprice: $$(global_gasprice("_global")),
      gasmax: $$(global_gasmax("_global")),
      dead: $$(global_dead("_global")) > 0
    });
    ret.local = DC.Local({
      active: $$(local_active("_local")) > 0,
      gasbase: $$(local_gasbase("_local")),
      fee: $$(local_fee("_local")),
      density: $$(local_density("_local")),
      best: $$(local_best("_local")),
      lock: $$(local_lock("_local")) > 0,
      lastId: $$(local_lastId("_local"))
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
        prev: $$(offer_prev("offer")),
        next: $$(offer_next("offer")),
        wants: $$(offer_wants("offer")),
        gives: $$(offer_gives("offer")),
        gasprice: $$(offer_gasprice("offer"))
      });

    bytes32 offerDetail = dex.offerDetails(base, quote, offerId);

    DC.OfferDetail memory offerDetailStruct =
      DC.OfferDetail({
        maker: $$(offerDetail_maker("offerDetail")),
        gasreq: $$(offerDetail_gasreq("offerDetail")),
        gasbase: $$(offerDetail_gasbase("offerDetail"))
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
    return $$(local_best("local"));
  }

  /* Convenience function to check whether given pair is locked */
  function isLocked(
    Dex dex,
    address base,
    address quote
  ) internal view returns (bool) {
    bytes32 local = dex.locals(base, quote);
    return $$(local_lock("local")) > 0;
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
