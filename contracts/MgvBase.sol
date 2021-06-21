// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;
import {MgvCommon as MC, MgvEvents, IMgvMonitor} from "./MgvCommon.sol";

/*
   These contracts describe an orderbook-based exchange ("the Mangrove") where market makers *do not have to provision their offer*. See `structs.js` for a longer introduction. In a nutshell: each offer created by a maker specifies an address (`maker`) to call upon offer execution by a taker. In the normal mode of operation ('Flash Maker'), the Mangrove transfers the amount to be paid by the taker to the maker, calls the maker, attempts to transfer the amount promised by the maker to the taker, and reverts if it cannot.

   There is one Mangrove contract that manages all tradeable pairs. This reduces deployment costs for new pairs and makes it easier to have maker provisions for all pairs in the same place.

   There is a secondary mode of operation ('Flash Taker') in which the _maker_ flashloans the sold amount to the taker.

   The Mangrove contract is `abstract` and accomodates both modes. Two contracts, `MMgv` (Maker Mangrove) and `TMgv` (Taker Mangrove) inherit from it, one per mode of operation.

   The contract structure is as follows:
   <img src="./Modular%20Mangrove.png" width="200%"> </img>
 */
contract MgvBase {
  /* # State variables */
  //+clear+
  /* The `vault` address. If a pair has fees >0, those fees are sent to the vault. */
  address public vault;

  /* Global mgv configuration, encoded in a 256 bits word. The information encoded is detailed in `structs.js`. */
  bytes32 public global;
  /* Configuration mapping for each token pair. The information is also detailed in `structs.js`. */
  mapping(address => mapping(address => bytes32)) public locals;

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

  /* # Configuration Reads */

  function config(address base, address quote)
    public
    returns (bytes32 _global, bytes32 _local)
  {
    _global = global;
    _local = locals[base][quote];
    if ($$(global_useOracle("_global")) > 0) {
      (uint gasprice, uint density) =
        IMgvMonitor($$(global_monitor("_global"))).read(base, quote);
      _global = $$(set_global("_global", [["gasprice", "gasprice"]]));
      _local = $$(set_local("_local", [["density", "density"]]));
    }
  }

  /* Returns the configuration in an ABI-compatible struct. Should not be called internally, would be a huge memory copying waste. Use `config` instead. */
  function getConfig(address base, address quote)
    external
    returns (MC.Config memory ret)
  {
    (bytes32 _global, bytes32 _local) = config(base, quote);
    ret.global = MC.Global({
      monitor: $$(global_monitor("_global")),
      useOracle: $$(global_useOracle("_global")) > 0,
      notify: $$(global_notify("_global")) > 0,
      gasprice: $$(global_gasprice("_global")),
      gasmax: $$(global_gasmax("_global")),
      dead: $$(global_dead("_global")) > 0
    });
    ret.local = MC.Local({
      active: $$(local_active("_local")) > 0,
      overhead_gasbase: $$(local_overhead_gasbase("_local")),
      offer_gasbase: $$(local_offer_gasbase("_local")),
      fee: $$(local_fee("_local")),
      density: $$(local_density("_local")),
      best: $$(local_best("_local")),
      lock: $$(local_lock("_local")) > 0,
      last: $$(local_last("_local"))
    });
  }

  /* Convenience function to get best offer of the given pair */
  function best(address base, address quote) external view returns (uint) {
    bytes32 local = locals[base][quote];
    return $$(local_best("local"));
  }

  /* Convenience function to check whether given pair is locked */
  function locked(address base, address quote) external view returns (bool) {
    bytes32 local = locals[base][quote];
    return $$(local_lock("local")) > 0;
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

  /*
  # Gatekeeping

  Gatekeeping functions are safety checks called in various places.
  */

  /* `unlockedMarketOnly` protects modifying the market while an order is in progress. Since external contracts are called during orders, allowing reentrancy would, for instance, let a market maker replace offers currently on the book with worse ones. Note that the external contracts _will_ be called again after the order is complete, this time without any lock on the market.  */
  function unlockedMarketOnly(bytes32 local) internal pure {
    require($$(local_lock("local")) == 0, "mgv/reentrancyLocked");
  }

  /* <a id="Mangrove/definition/liveMgvOnly"></a>
     In case of emergency, the Mangrove can be `kill`ed. It cannot be resurrected. When a Mangrove is dead, the following operations are disabled :
       * Executing an offer
       * Sending ETH to the Mangrove the normal way. Usual [shenanigans](https://medium.com/@alexsherbuck/two-ways-to-force-ether-into-a-contract-1543c1311c56) are possible.
       * Creating a new offer
   */
  function liveMgvOnly(bytes32 _global) internal pure {
    require($$(global_dead("_global")) == 0, "mgv/dead");
  }

  /* When the Mangrove is deployed, all pairs are inactive by default (since `locals[base][quote]` is 0 by default). Offers on inactive pairs cannot be taken or created. They can be updated and retracted. */
  function activeMarketOnly(bytes32 _global, bytes32 _local) internal pure {
    liveMgvOnly(_global);
    require($$(local_active("_local")) > 0, "mgv/inactive");
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
