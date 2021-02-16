// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

/* # Structs
/* The structs defined in `structs.js` have their counterpart as solidity structs that are easy to manipulate for outside contracts / callers of view functions. */
library DexCommon {
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
    uint gasbase;
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
    uint gasbase;
    bool lock;
    uint best;
    uint lastId;
  }

  struct Config {
    Global global;
    Local local;
  }

  /*
   Some miscellaneous things useful to both `Dex` and `DexLib`:*/
  //+clear+

  /* Holds data about orders in a struct, used by `marketOrder` and `internalSnipes` (and some of their nested functions) to avoid stack too deep errors. */
  struct SingleOrder {
    address base;
    address quote;
    uint offerId;
    bytes32 offer;
    /* will evolve over time, initially the wants/gives from the taker's pov,
       then actual wants/give depending on how much the offer is ready */
    uint wants;
    uint gives;
    /* only populated when necessary */
    bytes32 offerDetail;
    bytes32 global;
    bytes32 local;
  }

  struct OrderResult {
    bool success;
    bytes32 makerData;
    bytes32 errorCode;
  }
}

/* # Events
The events emitted for use by various bots are listed here: */
library DexEvents {
  /* * Emitted at the creation of the new Dex contract on the pair (`quote`, `base`)*/
  event NewDex();

  event TestEvent(uint);

  /* * Dex adds or removes wei from `maker`'s account */
  event Credit(address maker, uint amount);
  event Debit(address maker, uint amount);

  /* * Dex reconfiguration */
  event SetActive(address base, address quote, bool value);
  event SetFee(address base, address quote, uint value);
  event SetGasbase(uint value);
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
    address taker,
    uint takerWants,
    uint takerGives
  );
  event MakerFail(
    address base,
    address quote,
    uint offerId,
    address taker,
    uint takerWants,
    uint takerGives,
    bytes32 errorCode,
    bytes32 makerData
  );

  /* * Permit */
  event Approval(
    address base,
    address quote,
    address owner,
    address spender,
    uint value
  );

  /* * Dex closure */
  event Kill();

  /* * A new offer was inserted into book.
   `maker` is the address of the contract that implements the offer. */
  event WriteOffer(address base, address quote, address maker, bytes32 data);

  /* * `offerId` was present and is now removed from the book. */
  event RetractOffer(address base, address quote, uint offerId);

  /* * Dead offer `offerId` is collected: provision is withdrawn and `offerId` is removed from `offers` and `offerDetails` maps*/
  event DeleteOffer(address base, address quote, uint offerId);
}

/* # IMaker interface */
interface IMaker {
  /* Called upon offer execution */
  function makerTrade(DexCommon.SingleOrder calldata order)
    external
    returns (bytes32);

  /* Called after all offers of an order have been executed. */
  function makerPosthook(
    DexCommon.SingleOrder calldata order,
    DexCommon.OrderResult calldata result
  ) external;

  event Execute(
    address dex,
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  );
}

/* # ITaker interface */
interface ITaker {
  // Inverted dex only: taker acquires enough base to pay back quote loan
  function takerTrade(
    address base,
    address quote,
    uint totalGot,
    uint totalGives
  ) external;
}

/* # Monitor interface */
interface IDexMonitor {
  function notifySuccess(DexCommon.SingleOrder calldata sor, address taker)
    external;

  function notifyFail(DexCommon.SingleOrder calldata sor, address taker)
    external;

  function read(address base, address quote)
    external
    returns (uint gasprice, uint density);
}
