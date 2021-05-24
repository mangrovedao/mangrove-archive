// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

$(sol_struct_defs)

/* # Structs
The structs defined in `structs.js` have their counterpart as solidity structs that are easy to manipulate for outside contracts / callers of view functions. */
library MgvCommon {
  struct Offer {
    uint prev;
    uint next;
    uint gives;
    uint wants;
    uint gasprice;
  }

  struct OfferDetail {
    address maker;
    uint gasreq;
    uint overhead_gasbase;
    uint offer_gasbase;
  }
  struct Global {
    address monitor;
    bool useOracle;
    bool notify;
    uint gasprice;
    uint gasmax;
    bool dead;
  }

  struct Local {
    bool active;
    uint fee;
    uint density;
    uint overhead_gasbase;
    uint offer_gasbase;
    bool lock;
    uint best;
    uint last;
  }

  struct Config {
    Global global;
    Local local;
  }

  /*
   Some miscellaneous data types useful to `Mangrove` and external contracts */
  //+clear+

  /* `SingleOrder` holds data about an order-offer match in a struct. Used by `marketOrder` and `internalSnipes` (and some of their nested functions) to avoid stack too deep errors. */
  struct SingleOrder {
    address base;
    address quote;
    uint offerId;
    $(sol_type_decl_offer) offer;
    /* `wants`/`gives` mutate over execution. Initially the `wants`/`gives` from the taker's pov, then actual `wants`/`gives` adjusted by offer's price and volume. */
    uint wants;
    uint gives;
    /* `offerDetail` is only populated when necessary. */
    $(sol_type_decl_offerDetail) offerDetail;
    $(sol_type_decl_global) global;
    $(sol_type_decl_local) local;
  }

  struct OrderResult {
    bool success;
    bytes32 makerData;
    bytes32 errorCode;
  }
}

/* # Events
The events emitted for use by bots are listed here: */
library MgvEvents {
  /* * Emitted at the creation of the new Mangrove contract on the pair (`quote`, `base`)*/
  event NewMgv();

  /* * Mangrove adds or removes wei from `maker`'s account */
  /* *Credit event occurs when an offer is removed from the Mangrove or when the `fund` function is called*/
  event Credit(address maker, uint amount);
  /* *Debit event occurs when an offer is posted or when the `withdraw` function is called*/
  event Debit(address maker, uint amount);

  /* * Mangrove reconfiguration */
  event SetActive(address base, address quote, bool value);
  event SetFee(address base, address quote, uint value);
  event SetGasbase(uint overhead_gasbase, uint offer_gasbase);
  event SetGovernance(address value);
  event SetMonitor(address value);
  event SetVault(address value);
  event SetUseOracle(bool value);
  event SetNotify(bool value);
  event SetGasmax(uint value);
  event SetDensity(address base, address quote, uint value);
  event SetGasprice(uint value);

  /* * Offer execution */
  event Success(
    address base,
    address quote,
    uint offerId,
    // maker's address is not logged because it can be retrieved from `WriteOffer` event using `offerId`, packed in `data`.
    address taker,
    uint takerWants,
    uint takerGives
  );
  event MakerFail(
    address base,
    address quote,
    uint offerId,
    // maker's address is not logged because it can be retrieved from `WriteOffer` event using `offerId`, packed in `data`.
    address taker,
    uint takerWants,
    uint takerGives,
    bytes32 errorCode,
    bytes32 makerData
  );

  /* * After `permit` and `approve` */
  event Approval(
    address base,
    address quote,
    address owner,
    address spender,
    uint value
  );

  /* * Mangrove closure */
  event Kill();

  /* * An offer was created or updated. `data` packs `makerWants`(96), `makerGives`(96), `gasprice`(16), `gasreq`(24), `offerId`(24)*/
  event WriteOffer(address base, address quote, address maker, $(sol_type_decl_writeOffer) data);

  /* * `offerId` was present and is now removed from the book. */
  event RetractOffer(address base, address quote, uint offerId);
}

/* # IMaker interface */
interface IMaker {
  /* Called upon offer execution. If this function reverts, Mangrove will not try to transfer funds. Returned data (truncated to 32 bytes) can be accessed during the call to `makerPosthook` in the `result.errorCode` field.
  Reverting with a message (for further processing during posthook) should be done using low level `revertTrade(bytes32)` provided in the `MgvIt` library. It is not possible to reenter the order book of the traded pair whilst this function is executed.*/
  function makerTrade(MgvCommon.SingleOrder calldata order)
    external
    returns (bytes32);

  /* Called after all offers of an order have been executed. Posthook of the last executed order is called first and full reentrancy into the Mangrove is enabled at this time. `order` recalls key arguments of the order that was processed and `result` recalls important information for updating the current offer.*/
  function makerPosthook(
    MgvCommon.SingleOrder calldata order,
    MgvCommon.OrderResult calldata result
  ) external;
}

/* # ITaker interface */
interface ITaker {
  /* FTD only: call to taker after loans went through */
  function takerTrade(
    address base,
    address quote,
    // total amount of base token that was flashloaned to the taker
    uint totalGot,
    // total amount of quote token that should be made available
    uint totalGives
  ) external;
}

/* # Monitor interface
If enabled, the monitor receives notification after each offer execution and is read for each pair's `gasprice` and `density`. */
interface IMgvMonitor {
  function notifySuccess(MgvCommon.SingleOrder calldata sor, address taker)
    external;

  function notifyFail(MgvCommon.SingleOrder calldata sor, address taker)
    external;

  function read(address base, address quote)
    external
    returns (uint gasprice, uint density);
}
