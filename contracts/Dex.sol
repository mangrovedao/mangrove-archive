// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
// Encode structs
pragma experimental ABIEncoderV2;
// ERC, Maker, Taker interfaces
import "./interfaces.sol";
// Types common to main Dex contract and DexLib
import {DexCommon as DC, DexEvents} from "./DexCommon.sol";
// The purpose of DexLib is to keep Dex under the [Spurious Dragon](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-170.md) 24kb limit.
import "./DexLib.sol";
import "./lib/HasAdmin.sol";

/* # State variables
   This contract describes an orderbook-based exchange ("Dex") where market makers *do not have to provision their offer*. See `DexCommon.sol` for a longer introduction. In a nutshell: each offer created by a maker specifies an address (`maker`) to call upon offer execution by a taker. The Dex transfers the amount to be paid by the taker to the maker, calls the maker, attempts to transfer the amount promised by the maker to the taker, and reverts if it cannot.


   One Dex instance is only an `OFR_TOKEN`/`REQ_TOKEN` market. For a `REQ_TOKEN`/`OFR_TOKEN` market, one should create another Dex instance with the two tokens swapped.

   The state variables are:
 */

contract Dex is HasAdmin {
  /* * The contract who deployed the dex */
  address private immutable DEPLOYER;
  /* The signature of the low-level swapping function. */
  bytes4 immutable SWAPPER;

  /* * An offer `id` is defined by two structs, `Offer` and `OfferDetail`, defined in `DexCommon.sol`.
   * `offers[id]` contains pointers to the `prev`ious (better) and `next` (worse) offer in the book, as well as the price and volume of the offer (in the form of two absolute quantities, `wants` and `gives`).
   * `offerDetails[id]` contains the market maker's address (`maker`), the amount of gas required by the offer (`gasreq`) as well cached values for the global `gasbase` and `gasprice` when the offer got created (see `DexCommon` for more on `gasbase` and `gasprice`).
   */
  mapping(address => mapping(address => mapping(uint => DC.Offer)))
    private offers;
  mapping(uint => DC.OfferDetail) private offerDetails;

  /* * Makers provision their possible penalties in the `freeWei` mapping.

       Offers specify the amount of gas they require for successful execution (`gasreq`). To minimize book spamming, market makers must provision a *penalty*, which depends on their `gasreq`. This provision is deducted from their `freeWei`. If an offer fails, part of that provision is given to the taker, as compensation. The exact amount depends on the gas used by the offer before failing.

       The Dex keeps track of their available balance in the `freeWei` map, which is decremented every time a maker creates a new offer (new offer creation is in `DexLib`).
   */
  mapping(address => uint) private freeWei;

  /* * `lastId` is a counter for offer ids, incremented every time a new offer is created. It can't go above 2^32-1. */
  uint private lastId;

  /* * If `reentrancyLock` is > 1, orders may not be added nor executed.

       Reentrancy during offer execution is not considered safe:
       * during execution, an offer could consume other offers further up in the book, effectively frontrunning the taker currently executing the offer.
       * it could also cancel other offers, creating a discrepancy between the advertised and actual market price at no cost to the maker.
       * an offer insertion consumes an unbounded amount of gas (because it has to be correctly placed in the book).

       Note: An optimization in the `marketOrder` function relies on reentrancy being forbidden.
   */
  mapping(address => mapping(address => uint)) locks;

  /* `best` is a struct with a single field holding the current best offer id. The id is wrapped in a struct so it can be passed to `DexLib`. */
  mapping(address => mapping(address => uint)) bests;

  /*
  # Dex Constructor

  A new Dex instance manages one side of a book; it offers `OFR_TOKEN` in return for `REQ_TOKEN`. To initialize a new instance, the deployer must provide initial configuration (see `DexCommon.sol` for more on configuration parameters):
  */
  constructor(
    /* determines whether the taker or maker does the flashlend */
    bool takerLends
  ) HasAdmin() {
    DEPLOYER = msg.sender;
    /* In a 'normal' mode of operation, takers lend the liquidity to the maker. */
    /* In an 'arbitrage' mode of operation, takers come ask the makers for liquidity. */
    SWAPPER = takerLends
      ? DexLib.swapTokens.selector
      : DexLib.invertedSwapTokens.selector;
    emit DexEvents.NewDex(address(this));
  }

  /*
  # Gatekeeping

  Gatekeeping functions start with `require` and are safety checks called in various places.
  */

  /* `requireNoReentrancyLock` protects modifying the book while an order is in progress. */
  function requireUnlocked(address ofrToken, address reqToken) internal view {
    require(locks[ofrToken][reqToken] < 2, "dex/reentrancyLocked");
  }

  /* * <a id="Dex/definition/requireLiveMarket"></a>
     In case of emergency, the Dex can be `kill()`ed. It cannot be resurrected. When a Dex is dead, the following operations are disabled :
       * Executing an offer
       * Sending ETH to the Dex (the normal way, usual shenanigans are possible)
       * Creating a new offerX
   */
  function requireLiveMarket(DC.Config memory _config) internal pure {
    require(!_config.dead, "dex/dead");
  }

  /* TODO documentation */
  function requireActiveMarket(DC.Config memory _config) internal pure {
    requireLiveMarket(_config);
    require(_config.active, "dex/inactive");
  }

  /* # Maker operations
     ## New Offer */
  //+clear+
  /* In the Dex, makers and takers call separate functions. Market makers call `newOffer` to fill the book, and takers call functions such as `simpleMarketOrder` to consume it.  */
  //+clear+

  /* The function `newOffer` is for market makers only; no match with the existing book is done. Makers specify how much `REQ_TOKEN` they `want` and how much `OFR_TOKEN` they are willing to `give`. They also specify how much gas should be given when executing their offer.

 _`gasreq` will determine the penalty provision set aside by the Dex from the market maker's `freeWei` balance._

  Offers are always inserted at the correct place in the book (for more on the book data structure, see `DexCommon.sol`). This requires walking through offers to find the correct insertion point. As in [Oasis](https://github.com/daifoundation/maker-otc/blob/master/src/matching_market.sol#L129), Makers should find the id of an offer close to theirs and provide it as `pivotId`.

  An offer cannot be inserted in a closed market, nor when reentrancy is disabled.

  No more than 2^32^-1 offers can ever be created.

  The [actual content of the function](#DexLib/definition/newOffer) is in `DexLib`, due to size limitations.
  */
  function newOffer(
    address ofrToken,
    address reqToken,
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) external returns (uint) {
    requireUnlocked(ofrToken, reqToken);
    DC.Config memory _config = config();
    uint newLastId = ++lastId;
    requireActiveMarket(_config);
    require(uint32(newLastId) == newLastId, "dex/offerIdOverflow");

    DC.OfferPack memory ofp =
      DC.OfferPack({
        ofrToken: ofrToken,
        reqToken: reqToken,
        wants: wants,
        gives: gives,
        id: newLastId,
        gasreq: gasreq,
        pivotId: pivotId,
        config: config()
      });
    return DexLib.newOffer(ofp, freeWei, offers, offerDetails, bests);
  }

  /* ## Cancel Offer */
  //+clear+
  /* `cancelOffer` is available in closed markets, but only outside of reentrancy. Upon successful deletion of an offer, the ETH that were provisioned are returned to the maker as `freeWei` balance. */
  function cancelOffer(
    address ofrToken,
    address reqToken,
    uint offerId
  ) external returns (uint provision) {
    requireUnlocked(ofrToken, reqToken);
    DC.Offer memory offer = offers[ofrToken][reqToken][offerId];
    if (!DC.isOffer(offer)) {
      return 0; //no effect on offers absent from the offer book
    }
    DC.OfferDetail memory offerDetail = offerDetails[offerId];
    require(msg.sender == offerDetail.maker, "dex/cancelOffer/unauthorized");

    dirtyDeleteOffer(ofrToken, reqToken, offerId);
    stitchOffers(ofrToken, reqToken, offer.prev, offer.next);

    /* Without a cast to `uint`, the operations convert to the larger type (gasprice) and may truncate */
    provision =
      offerDetail.gasprice *
      (uint(offerDetail.gasreq) + offerDetail.gasbase);
    DexLib.creditWei(freeWei, msg.sender, provision);
  }

  /* ## Provisioning
  Market makers must have enough provisions for possible penalties. These provisions are in ETH. Every time a new offer is created, the `freeWei` balance is decreased by the amount necessary to provision the offer's maximum possible penalty. */
  //+clear+

  /* A transfer with enough gas to the Dex will increase the caller's available `freeWei` balance. _You should send enough gas to execute this function when sending money to the Dex._  */
  receive() external payable {
    requireLiveMarket(config());
    DexLib.creditWei(freeWei, msg.sender, msg.value);
  }

  /* The remaining balance of a Maker (excluding the penalties currently locked in pending offers) can read with `balanceOf(address)` and withdrawn with `withdraw(uint)`.*/
  function balanceOf(address maker) external view returns (uint) {
    return freeWei[maker];
  }

  /* Any provision not currently held to secure an offer's possible penalty is available for withdrawal. */
  function withdraw(uint amount) external returns (bool success) {
    /* Since we only ever send money to the caller, we do not need to provide any particular amount of gas, the caller can manage that themselves. Still, as nonzero value calls provide a 2300 gas stipend, a `withdraw(0)` would trigger a call with actual 0 gas. */
    //if (amount == 0) return;
    //+clear+
    DexLib.debitWei(freeWei, msg.sender, amount);
    (success, ) = msg.sender.call{gas: 0, value: amount}("");
  }

  /* # Taker operations */
  //+clear+

  /* ## Market Order */
  //+clear+
  /*  `simpleMarketOrder` walks the book and takes offers up to a certain volume of `OFR_TOKEN` and for a maximum average price. */
  function simpleMarketOrder(
    address ofrToken,
    address reqToken,
    uint takerWants,
    uint takerGives
  ) external {
    marketOrder(
      ofrToken,
      reqToken,
      takerWants,
      takerGives,
      0,
      bests[ofrToken][reqToken]
    );
  }

  /* The lower-level `marketOrder` can:
   * collect a list of failed offers for further processing (see [punishment for failing offers](#dex.sol-punishment-for-failing-offers)).
   * start walking the OB from any offerId (`0` to start from the best offer).
   */
  //+ignore+ ask for a volume by setting takerWants to however much you want and
  //+ignore+ takerGive to max_uint. Any price will be accepted.

  //+ignore+ ask for an average price by setting takerGives such that gives/wants is the price

  //+ignore+ there is no limit price setting

  //+ignore+ setting takerWants to max_int and takergives to however much you're ready to spend will
  //+ignore+ not work, you'll just be asking for a ~0 price.

  /* During execution, we store some values in a memory struct to avoid solc's [stack too deep errors](https://medium.com/coinmonks/stack-too-deep-error-in-solidity-608d1bd6a1ea) that can occur when too many local variables are used. */

  function marketOrder(
    /*   ### Arguments */
    /* A taker calling this function wants to receive `takerWants` `OFR_TOKEN` in return
       for at most `takerGives` `REQ_TOKEN`.

       A regular market order will have `punishLength = 0`, and `offerId = 0`. Any other `punishLength` and `offerId` are for book cleaning (see [`punishingMarketOrder`](#Dex/definition/punishingMarketOrder)).
     */
    address ofrToken,
    address reqToken,
    uint takerWants,
    uint takerGives,
    uint punishLength,
    uint offerId
  )
    public
    returns (
      /* The return value is used for book cleaning: it contains a list (of length `2 * punishLength`) of the offers that failed during the market order, along with the gas they used before failing. */
      uint[2][] memory
    )
  {
    DC.OrderPack memory orp;
    orp.ofrToken = ofrToken;
    orp.reqToken = reqToken;
    orp.offerId = offerId;
    orp.offer = offers[ofrToken][reqToken][offerId];
    orp.config = config();
    orp.failures = new uint[2][](punishLength);

    /* ### Checks */
    //+clear+
    /* For the market order to even start, the market needs to be both alive (that is, not irreversibly killed following emergency action), and not currently protected from reentrancy. */
    DC.Config memory _config = config();
    requireActiveMarket(_config);
    requireUnlocked(orp.ofrToken, orp.reqToken);

    /* Since amounts stored in offers are 96 bits wide, checking that `takerWants` fits in 160 bits prevents overflow during the main market order loop. */
    require(
      uint160(takerWants) == takerWants,
      "dex/marketOrder/takerWants/160bits"
    );

    /* ### Initialization */
    /* The market order will operate as follows : it will go through offers from best to worse, starting from `offerId`, and: */
    /* * will maintain remaining `takerWants` and `takerGives` values. Their initial ratio is the average price the taker will accept. Better prices may be found early in the book, and worse ones later.
     * will not set `prev`/`next` pointers to their correct locations at each offer taken (this is an optimization enabled by forbidding reentrancy).
     * after consuming a segment of offers, will connect the `prev` and `next` neighbors of the segment's ends.
     * Will maintain an array of pairs `(offerId, gasUsed)` to identify failed offers. Look at [punishment for failing offers](#dex.sol-punishment-for-failing-offers) for more information. Since there are no extensible in-memory arrays, `punishLength` should be an upper bound on the number of failed offers. */
    //+clear+

    /* This check is subtle. We believe the only check that is really necessary here is `offerId != 0`, because any other wrong offerId would point to an empty offer, which would be detected upon division by `offer.gives` in the main loop (triggering a revert). However, with `offerId == 0`, we skip the main loop and try to stitch `pastOfferId` with `offerId`. Basically at this point we're "trusting" `offerId`. This sets `best = 0` and breaks the offer book if it wasn't empty. Out of caution we do a more general check and make sure that the offer exists. */
    require(DC.isOffer(orp.offer), "dex/marketOrder/noSuchOffer");

    uint initialTakerWants = takerWants;
    uint pastOfferId = orp.offer.prev;

    uint minOrderSize = orp.config.density * orp.config.gasbase;

    locks[orp.ofrToken][orp.reqToken] = 2;

    /* ### Main loop */
    //+clear+
    /* Offers are looped through until:
     * the remaining amount wanted by the taker is smaller than the current minimum offer size,
     * or `offerId == 0`, which means we've gone past the end of the book. */
    while (takerWants >= minOrderSize && orp.offerId != 0) {
      /* #### `makerWouldWant` */
      //+clear+
      /* The current offer has a price <code>_p_ = offer.wants/offer.gives</code>. `makerWouldWant` is the amount of `REQ_TOKEN` the offer would require at price _p_ to provide `takerWants` `OFR_TOKEN`. Computing `makeWouldWant` gives us both a test that _p_ is an acceptable price for the taker, and the amount of `REQ_TOKEN` to send to the maker.

    **Note**: We never check that `offerId` is actually a `uint32`, or that `offerId` actually points to an offer: it is not possible to insert an offer with an id larger than that, and a wrong `offerId` will point to a zero-initialized offer, which will revert the call when dividing by `offer.gives`.

   **Note**: Since `takerWants` fits in 160 bits and `offer.wants` fits in 96 bits, the multiplication does not overflow. Since division rounds towards 0, the maker may have to accept a price slightly worse than expected.
       */
      uint makerWouldWant = (takerWants * orp.offer.wants) / orp.offer.gives;

      /* We set `makerWouldWant > 0` to prevent takers from leaking money out of makers for free. */
      if (makerWouldWant == 0) makerWouldWant = 1;

      /* #### Offer taken */
      if (makerWouldWant <= takerGives) {
        /* If the current offer is good enough for the taker can accept, we compute how much the taker should give/get on the _current offer_. So: `takerWants`,`takerGives` are the residual of how much the taker wants to trade overall, while `orp.wants`,`orp.gives` are how much the taker will trade with the current offer. */
        (orp.wants, orp.gives) = orp.offer.gives < takerWants
          ? (orp.offer.gives, orp.offer.wants)
          : (takerWants, makerWouldWant);

        /* Execute the offer after loaning money to the maker. The last argument to `executeOffer` is `true` to flag that pointers shouldn't be updated (thus saving writes). The returned values are explained below: */
        (bool success, uint gasUsedIfFailure, bool deleted) =
          executeOffer(orp, true);

        /* `success` means that the maker delivered `localTakerWants` `OFR_TOKEN` to the taker. We update the total amount wanted and spendable by the taker (possibly changing the remaining average price). */
        if (success) {
          emit DexEvents.Success(orp.offerId, orp.wants, orp.gives);
          takerWants -= orp.wants;
          takerGives -= orp.gives;
          /*
          If `!success`, the maker failed to deliver `localTakerWants`. In that case `gasUsedIfFailure` is nonzero and will be used to apply a penalty (penalties are applied in proportion with wasted gas).

          Note that partial fulfillment of the amount requested in `localTakerWants` is not taken into account. Any delivery strictly less than `localTakerWants` will trigger a rollback and be considered a failure.
          */
        } else {
          emit DexEvents.Failure(orp.offerId, orp.wants, orp.gives);
          /* For penalty application purposes (never triggered if `punishLength = 0`), store the offer id and the gas wasted by the maker */
          if (orp.numFailures < orp.failures.length) {
            orp.failures[orp.numFailures] = [orp.offerId, gasUsedIfFailure];
            orp.numFailures++;
          }
        }
        /* Finally, update `offerId`/`offer` to the next available offer _only if the current offer was deleted_.

           Let _r~1~_, ..., _r~n~_ the successive values taken by `offer` each time the current while loop's test is executed.
           Also, let _r~0~_ = `offers[pastOfferId]` be the offer immediately better
           than _r~1~_.
           After the market order loop ends, we will restore the doubly linked
           list by connecting _r~0~_ to _r~n~_ through their `prev`/`next`
           pointers. Assume that currently, `offer` is _r~i~_. Should
        we update `offer` to some _r~i+1~_ or is _i_ = _n_?

         * If _r~i~_ was `deleted`, we may or may not be at the last loop iteration, but we will stitch _r~0~_ to some _r~j~_, _j > i_, so we update `offer` to _r~i+1~_ regardless.
          * if _r~i~_ was not `deleted`, we are at the last loop iteration (see why below). So we will stitch _r~0~_ to _r~i~_ = _r~n~_. In that case, we must not update `offer`.

          Note that if the invariant _"not `deleted` → end of `while` loop"_ does not hold, the market order is completely broken.


            Proof that we are at the last iteration of the while loop: if what's left in the offer after a successful execution is above the minimum size offer, we update the offer and keep it in the book: in `executeOffer`, the offer is not deleted iff the test below passes (variables renamed for clarity):
           ```
           success &&
           gives - localTakerwants >=
             density * (gasreq + gasbase)
           ```
          By the `Sauron` contract, `density * gasbase > 0`, so by the test above `offer.gives - localTakerWants > 0`, so by definition of `localTakerWants`, `localTakerWants == takerWants`. So after updating `takerWants` (the line `takerWants -= localTakerWants`), we have
          ```
           takerWants == 0 < density * gasbase
          ```
          And so the loop ends.
        */
        if (deleted) {
          orp.offerId = orp.offer.next;
          orp.offer = offers[orp.ofrToken][orp.reqToken][orp.offerId];
        }
        /* #### Offer not taken */
        //+clear+
        /* This branch is selected if the current offer is strictly worse than the taker can accept. Currently, we interrupt the loop and let the taker leave with less than they asked for (but at a correct price). We could also revert instead of breaking; this could be a configurable flag for the taker to pick. */
      } else {
        break;
      }
    }
    /* ### Post-while loop */
    //+clear+
    /* `applyFee` extracts the fee from the taker, proportional to the amount purchased (which is `initialTakerWants - takerWants`). */
    applyFee(orp.ofrToken, orp.config.fee, initialTakerWants - takerWants);
    locks[orp.ofrToken][orp.reqToken] = 1;
    /* After exiting the loop, we connect the beginning & end of the segment just consumed by the market order. */
    stitchOffers(orp.ofrToken, orp.reqToken, pastOfferId, orp.offerId);

    /* The `failures` array initially has size `punishLength`. To remember the number of failures actually stored in `failures` (which can be strictly less than `punishLength`), we store `numFailures` in the length field of `failures`. This also saves on the amount of memory copied in the return value.

       The line below is hackish though, and we may want to just return a `(uint,uint[2][])` pair.
    */
    uint numFailures = orp.numFailures;
    uint[2][] memory failures = orp.failures;
    assembly {
      mstore(failures, numFailures)
    }
    return failures;
  }

  /* ## Sniping */
  //+clear+
  /* `snipe` takes a single offer from the book, at whatever price is induced by the offer. */
  function snipe(
    address ofrToken,
    address reqToken,
    uint offerId,
    uint takerWants
  ) external returns (bool) {
    uint[2][] memory targets = new uint[2][](1);
    targets[0] = [offerId, takerWants];
    uint[2][] memory failures = internalSnipes(ofrToken, reqToken, targets, 1);
    return (failures.length == 0);
  }

  //+clear+
  /*
     From an array of _n_ `(offerId, takerWants)` pairs (encoded as a `uint[2][]` of size _2n_)
     execute each snipe in sequence.

     Also accepts an optional `punishLength` (as in
    `marketOrder`). Returns an array of size at most
    twice `punishLength` containing info on failed offers. Only existing offers can fail: if an offerId is invalid, it will just be skipped. **You should probably set `punishLength` to 1.**
      */
  function internalSnipes(
    address ofrToken,
    address reqToken,
    uint[2][] memory targets,
    uint punishLength
  ) public returns (uint[2][] memory) {
    /* ### Pre-loop Checks */
    //+clear+
    DC.Config memory _config = config();
    requireActiveMarket(_config);
    requireUnlocked(ofrToken, reqToken);

    /* ### Pre-loop initialization */
    //+clear+

    DC.OrderPack memory orp;
    orp.config = config();
    orp.ofrToken = ofrToken;
    orp.reqToken = reqToken;
    orp.failures = new uint[2][](punishLength);

    uint takerGot;
    locks[ofrToken][reqToken] = 2;
    /* ### Main loop */
    //+clear+

    for (uint i = 0; i < targets.length; i++) {
      /* ### In-loop initilization */
      /* At each iteration, we extract the current `offerId` and `takerWants` */
      orp.offerId = targets[i][0];

      uint takerWants = targets[i][1];
      orp.offer = offers[orp.ofrToken][orp.reqToken][orp.offerId];

      /* If we removed the `isOffer` conditional, a single expired or nonexistent offer in `targets` would revert the entire transaction (by the division by `offer.gives` below). If the taker wants the entire order to fail if at least one offer id is invalid, it suffices to set `punishLength > 0` and check the length of the return value. */
      if (DC.isOffer(orp.offer)) {
        /* `localTakerWants` bounds the amount requested by the taker (`takerWants`) by the maximum amount on offer. It also obviates the need to check the size of `takerWants`: while in a market order we must compare the price a taker accepts with the offer price, here we just accept the offer's price. So if `takerWants` does not fit in 96 bits (the size of `offer.gives`), it won't be used in the line below. */
        orp.wants = orp.offer.gives < takerWants ? orp.offer.gives : takerWants;

        /* `localTakerGives` is the amount to be paid using the price induced by the offer. */
        orp.gives = (orp.wants * orp.offer.wants) / orp.offer.gives;

        /* We set `localTakerGives > 0` to prevent takers from leaking money out of makers for free. */
        if (orp.gives == 0) orp.gives = 1;

        /* We execute the offer with the flag `dirtyDeleteOffer` set to `false`, so the offers before and after the selected one get stitched back together. */
        (bool success, uint gasUsedIfFailure, ) = executeOffer(orp, false);
        /* For punishment purposes (never triggered if `punishLength = 0`), we store the offer id and the gas wasted by the maker */
        if (success) {
          emit DexEvents.Success(orp.offerId, orp.wants, orp.gives);
          takerGot += orp.wants;
        } else {
          emit DexEvents.Failure(orp.offerId, orp.wants, orp.gives);
          if (orp.numFailures < orp.failures.length) {
            orp.failures[orp.numFailures] = [orp.offerId, gasUsedIfFailure];
            orp.numFailures++;
          }
        }
      }
    }
    /* `applyFee` extracts the fee from the taker, proportional to the amount purchased */
    applyFee(orp.ofrToken, orp.config.fee, takerGot);
    locks[orp.ofrToken][orp.reqToken] = 1;
    /* The `failures` array initially has size `punishLength`. To remember the number of failures actually stored in `failures` (which can be strictly less than `punishLength`), we store `numFailures` in the length field of `failures`. This also saves on the amount of memory copied in the return value.

       The line below is hackish though, and we may want to just return a `(uint,uint[2][])` pair.
    */
    uint numFailures = orp.numFailures;
    uint[2][] memory failures = orp.failures;
    assembly {
      mstore(failures, numFailures)
    }
    return failures;
  }

  /* # Low-level offer deletion */
  /* Offer deletion is used when an offer has been consumed below the absolute dust limit and when an offer has failed. There are 2 steps to deleting an offer with id `id`: */
  //+clear+
  /* 1. Zero out `offers[id]` and `offerDetails[id]`. Apart from setting `offers[id].gives` to 0 (which is how we detect invalid offers), the rest is just for the gas refund. */
  function dirtyDeleteOffer(
    address ofrToken,
    address reqToken,
    uint offerId
  ) internal {
    delete offers[ofrToken][reqToken][offerId];
    delete offerDetails[offerId];
    emit DexEvents.DeleteOffer(offerId);
  }

  /* 2. Connect the predecessor and sucessor of `id` through their `next`/`prev` pointers. For more on the book structure, see `DexCommon.sol`. This step is not necessary during a market order, so we only call `dirtyDeleteOffer` */
  function stitchOffers(
    address ofrToken,
    address reqToken,
    uint past,
    uint future
  ) internal {
    if (past != 0) {
      offers[ofrToken][reqToken][past].next = uint32(future);
    } else {
      bests[ofrToken][reqToken] = future;
    }

    if (future != 0) {
      offers[ofrToken][reqToken][future].prev = uint32(past);
    }
  }

  /* # Low-level offer execution */
  //+clear+

  /* Both forms of sniping and market orders use the functions below, which execute (part of) an offer and return information about the execution.

     ## Offer execution
  */
  //+clear+
  /* The parameters `takerWants` and `takerGives` induce a price. This is an unsafe, internal function. Most importantly, it does not check that `takerWants/takerGives == offer.gives/offer.wants`, nor that `takerWants <= offer.gives`. Callers must do both of those checks, or various terrible things might happen: market makers may be asked for a price they did not commit to, and `uint` underflow may keep the offer after execution with a _much_ bigger `gives`.

  It would be nice to do those checks right here, in `executeOffer`. But market orders must make price computations necessary to those checks _before_ calling `executeOffer` anyway, so they can decide whether the offer should be executed at all or not. To save gas, we don't redo the checks here. */
  function executeOffer(
    DC.OrderPack memory orp,
    /* The last argument, `dirtyDelete`, is here for market orders: if true, `next`/`prev` pointers around the deleted offer are not reset properly. */
    bool dirtyDelete
  )
    internal
    returns (
      /* The return values indicate:
       * whether the maker `success`fully completed the transaction (failure of the taker to pay the initial amount triggers a revert),
       * (in case of failure) how much gas the maker consumed, and
       * whether the offer was deleted from the book (whether due to failure or because it has become dust). */
      bool success,
      uint gasUsedIfFailure,
      bool deleted
    )
  {
    /* `executeOffer` and `flashSwapTokens` are separated for clarity, but `flashSwapTokens` is only used by `executeOffer`. It manages the actual work of flashloaning tokens and applying penalties. */
    DC.OfferDetail memory offerDetail = offerDetails[orp.offerId];
    (success, gasUsedIfFailure) = flashSwapTokens(orp, offerDetail);

    /* After execution, there are four possible outcomes, along 2 axes: the transaction was successful (or not), the offer was consumed to below the absolute dust limit (or not).

    If the transaction was successful and the offer was not consumed too much, it stays on the book with updated values.

    Note how we use `config.gasbase` instead of `offerDetail.gasbase` to check dust limit. `offerDetail.gasbase` is used to correctly apply penalties; here we are making sure the offer  is still good enough according to the current configuration.

    */
    if (
      success &&
      orp.offer.gives - orp.wants >=
      orp.config.density * (offerDetail.gasreq + orp.config.gasbase)
    ) {
      offers[orp.ofrToken][orp.reqToken][orp.offerId].gives = uint96(
        orp.offer.gives - orp.wants
      );
      offers[orp.ofrToken][orp.reqToken][orp.offerId].wants = uint96(
        orp.offer.wants - orp.gives
      );
      deleted = false;
      /* Otherwise, it will be deleted. */
    } else {
      dirtyDeleteOffer(orp.ofrToken, orp.reqToken, orp.offerId);
      if (!dirtyDelete) {
        stitchOffers(
          orp.ofrToken,
          orp.reqToken,
          orp.offer.prev,
          orp.offer.next
        );
      }
      deleted = true;
    }
  }

  /* ## Flash swap */
  //+clear+
  /*
     We continue to drill down `executeOffer`. The function `flashSwapTokens` has 2 roles :
  1. measure gas used by executing the offer
  2. invoke penalty application,   */
  function flashSwapTokens(
    DC.OrderPack memory orp,
    DC.OfferDetail memory offerDetail
  ) internal returns (bool, uint) {
    /* We start by saving the amount of gas currently available so we can measure how much we spent later. */
    uint oldGas = gasleft();

    /* We will slightly overapproximate the gas consumed by the maker since some local operations will take place in addition to the call; the total cost must not exceed `config.gasbase`.

    Note that we use `config.gasbase`, not `offerDetail.gasbase`. `gasbase` is cached in `offerDetail` for the purpose of applying penalties; when checking if it's worth going through with taking an offer, we look at the most up-to-date `gasbase` value.
    */
    require(
      oldGas >= offerDetail.gasreq + orp.config.gasbase,
      "dex/unsafeGasAmount"
    );

    /* The flashswap is executed by delegatecall to `SWAPPER`. If the call reverts, it means the maker failed to send back `takerWants` `OFR_TOKEN` to the taker. If the call succeeds, `retdata` encodes a boolean indicating whether the taker did send enough to the maker or not. */
    (bool noRevert, bytes memory retdata) =
      address(DexLib).delegatecall(
        abi.encodeWithSelector(
          SWAPPER,
          orp.ofrToken,
          orp.reqToken,
          orp.offerId,
          orp.gives,
          orp.wants,
          offerDetail
        )
      );
    /* In both cases, we call `applyPenalty`, which splits the provisioned penalty (set aside during the `newOffer` call which created the offer between the taker and maker. */
    if (noRevert) {
      bool takerPaid = abi.decode(retdata, (bool));
      require(takerPaid, "dex/takerFailToPayMaker");
      applyPenalty(true, 0, offerDetail);
      return (true, 0);
    } else {
      uint gasUsed = oldGas - gasleft();
      applyPenalty(false, gasUsed, offerDetail);
      return (false, gasUsed);
    }
  }

  /* Post-trade, `applyFee` reaches back into the taker's pocket and extract a fee on the total amount of `OFR_TOKEN` transferred to them. */
  function applyFee(
    address ofrToken,
    uint fee,
    uint amount
  ) internal {
    if (amount > 0) {
      // amount is at most 160 bits wide and fee it at most 14 bits wide.
      uint concreteFee = (amount * fee) / 10000;
      bool success =
        DexLib.transferToken(ofrToken, msg.sender, admin, concreteFee);
      require(success, "dex/takerFailToPayDex");
    }
  }

  /* ## Penalties */
  //+clear+
  /* After any offer executes, or after calling a punishment function, `applyPenalty` sends part of the provisioned penalty to the maker, and part to the taker. */
  function applyPenalty(
    bool success,
    uint gasUsed,
    DC.OfferDetail memory offerDetail
  ) internal {
    /* We set `gasDeducted = min(gasUsed,gasreq)` since `gasreq < gasUsed` is possible (e.g. with `gasreq = 0`). */
    uint gasDeducted =
      gasUsed < offerDetail.gasreq ? gasUsed : offerDetail.gasreq;

    /*
       Then we apply penalties:

       * If the transaction was a success, we entirely refund the maker and send nothing to the taker.

       * Otherwise, the maker loses the cost of `gasDeducted + gasbase` gas. The gas price is estimated by `gasprice`.

         Note that to create the offer, the maker had to provision for `gasreq + gasbase` gas.

         Note that `offerDetail.gasbase` and `offerDetail.gasprice` are the values of the Dex parameters `config.gasbase` and `config.gasprice` when the offer was createdd. Without caching, the provision set aside could be insufficient to reimburse the maker (or to compensate the taker).

     */
    uint released =
      offerDetail.gasprice *
        (
          success
            ? offerDetail.gasreq + offerDetail.gasbase
            : offerDetail.gasreq - gasDeducted
        );

    DexLib.creditWei(freeWei, offerDetail.maker, released);

    if (!success) {
      uint amount = offerDetail.gasprice * (offerDetail.gasbase + gasDeducted);
      bool noRevert;
      (noRevert, ) = msg.sender.call{gas: 0, value: amount}("");
    }
  }

  /* # Punishment for failing offers */
  //+clear+

  /* Offers are just promises. They can fail. Penalty provisioning discourages from failing too much: we ask makers to provision more ETH than the expected gas cost of executing their offer and punish them accoridng to wasted gas.

     Under normal circumstances, we should expect to see bots with a profit expectation dry-running offers locally and executing `snipe` on failing offers, collecting the penalty. The result should be a mostly clean book for actual takers (i.e. a book with only successful offers).

     **Incentive issue**: if the gas price increases enough after an offer has been created, there may not be an immediately profitable way to remove the fake offers. In that case, we count on 3 factors to keep the book clean:
     1. Gas price eventually comes down.
     2. Other market makers want to keep the Dex attractive and maintain their offer flow.
     3. Dex administrators (who may collect a fee) want to keep the Dex attractive and maximize exchange volume.

We introduce convenience functions `punishingMarketOrder` and `punishingSnipes` so bots do not have to run their own contracts. They work by executing a sequence of offers, then reverting all the trades (whatever happened). The revert data contains the list of failed offers, which are then punished. */

  /* ## Snipes */
  //+clear+
  /* Run and revert a sequence of snipes so as to collect `offerId`s that are failing.
   `punishLength` is the number of failing offers one is trying to catch. */
  function punishingSnipes(
    address ofrToken,
    address reqToken,
    uint[2][] calldata targets,
    uint punishLength
  ) external {
    /* We do not directly call `snipes` because we want to revert all the offer executions before returning. So we call an intermediate function, `internalPunishingSnipes` (we don't `call` to preserve the calling context, in partiular `msg.sender`). */
    (bool noRevert, bytes memory retdata) =
      address(this).delegatecall(
        abi.encodeWithSelector(
          this.internalPunishingSnipes.selector,
          ofrToken,
          reqToken,
          targets,
          punishLength
        )
      );

    /* To avoid spurious capture of reverts (for instance a failed `require` in the pre-execution checks),
       `internalPunishingSnipes` returns normally with revert data if it detects a revert.
       So:
         * If `internalPunishingSnipes` returns normally, then _the sniping **did** revert_ and `retdata` is the revert data. In that case we "re-throw".
         * If it reverts, then _the sniping **did not** revert_ and `retdata` is an array of failed offers. We punish those offers. */
    if (noRevert) {
      evmRevert(abi.decode(retdata, (bytes)));
    } else {
      punish(ofrToken, reqToken, abi.decode(retdata, (uint[2][])));
    }
  }

  /* Sandwiched between `punishingSnipes` and `internalSnipes`, the function `internalPunishingSnipes` runs a sequence of snipes, reverts it, and sends up the list of failed offers. If it catches a revert inside `snipes`, it returns normally a `bytes` array with the raw revert data in it. Again, we use `delegatecall` to preseve `msg.sender`. */
  function internalPunishingSnipes(
    address ofrToken,
    address reqToken,
    uint[2][] calldata targets,
    uint punishLength
  ) external returns (bytes memory retdata) {
    bool noRevert;
    (noRevert, retdata) = address(this).delegatecall(
      abi.encodeWithSelector(
        this.internalSnipes.selector,
        ofrToken,
        reqToken,
        targets,
        punishLength
      )
    );

    /*
     * If `internalSnipes` returns normally, then _the sniping **did not** revert_ and `retdata` is an array of failed offers. In that case we revert.
     * If it reverts, then _the sniping **did** revert_ and `retdata` is the revert data. In that case we return normally. */
    if (noRevert) {
      evmRevert(retdata);
    } else {
      return retdata;
    }
  }

  /* ## Market order */
  //+clear+

  /* <a id="Dex/definition/punishingMarketOrder"></a> Run and revert a market order so as to collect `offerId`s that are failing.
   `punishLength` is the number of failing offers one is trying to catch. */
  function punishingMarketOrder(
    address ofrToken,
    address reqToken,
    uint fromOfferId,
    uint takerWants,
    uint takerGives,
    uint punishLength
  ) external {
    /* We do not directly call `marketOrder` because we want to revert all the offer executions before returning. So we delegatecall an intermediate function, `internalPunishingMarketOrder`. Again, we use `delegatecall` to preserve `msg.sender`. */
    (bool noRevert, bytes memory retdata) =
      address(this).delegatecall(
        abi.encodeWithSelector(
          this.internalPunishingMarketOrder.selector,
          ofrToken,
          reqToken,
          fromOfferId,
          takerWants,
          takerGives,
          punishLength
        )
      );

    /* To avoid spurious capture of reverts (for instance a failed `require` in the pre-execution checks),
       `internalPunishingMarketOrder` returns normally with revert data if it detects a revert.
       So:
         * If `internalPunishingMarketOrder` returns normally, then _the market order **did** revert_ and `retdata` is the revert data. In that case we "re-throw".
         * If it reverts, then _the market order **did not** revert_ and `retdata` is an array of failed offers. We punish those offers. */
    if (noRevert) {
      evmRevert(abi.decode(retdata, (bytes)));
    } else {
      punish(ofrToken, reqToken, abi.decode(retdata, (uint[2][])));
    }
  }

  /* Sandwiched between `punishingMarketOrder` and `marketOrder`, the function `internalPunishingMarketOrder` runs a market order, reverts it, and sends up the list of failed offers. If it catches a revert inside `marketOrder`, it returns normally a `bytes` array with the raw revert data in it. Again, we use `delegatecall` to preserve `msg.sender`. */
  function internalPunishingMarketOrder(
    address ofrToken,
    address reqToken,
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint punishLength
  ) external returns (bytes memory retdata) {
    bool noRevert;
    (noRevert, retdata) = address(this).delegatecall(
      abi.encodeWithSelector(
        this.marketOrder.selector,
        ofrToken,
        reqToken,
        takerWants,
        takerGives,
        punishLength,
        offerId
      )
    );

    /*
     * If `marketOrder` returns normally, then _the market order **did not** revert_ and `retdata` is an array of failed offers. In that case we revert.
     * If it reverts, then _the market order **did** revert_ and `retdata` is the revert data. In that case we return normally. */
    if (noRevert) {
      evmRevert(retdata);
    } else {
      return retdata;
    }
  }

  /* ## Low-level punish */
  //+clear+
  /* Given a sequence of `(offerId, gasUsed)` pairs, `punish` assumes they have failed and
     executes `applyPenalty` on them.  */
  function punish(
    address ofrToken,
    address reqToken,
    uint[2][] memory failures
  ) internal {
    uint failureIndex;
    while (failureIndex < failures.length) {
      uint id = failures[failureIndex][0];
      /* We read `offer` and `offerDetail` before calling `dirtyDeleteOffer`, since after that they will be erased. */
      DC.Offer memory offer = offers[ofrToken][reqToken][id];
      if (DC.isOffer(offer)) {
        DC.OfferDetail memory offerDetail = offerDetails[id];
        dirtyDeleteOffer(ofrToken, reqToken, id);
        stitchOffers(ofrToken, reqToken, offer.prev, offer.next);
        uint gasUsed = failures[failureIndex][1];
        applyPenalty(false, gasUsed, offerDetail);
      }
      failureIndex++;
    }
  }

  /* Given some `bytes`, `evmRevert` reverts the current call with the raw bytes as revert data. The length prefix is omitted. Prevents abi-encoding of solidity-revert's string argument.  */
  function evmRevert(bytes memory data) internal pure {
    uint length = data.length;
    assembly {
      revert(add(data, 32), length)
    }
  }

  /* # Get/set state

  /* ## State
     State getters are available for composing with other contracts & bots. */
  //+clear+
  // TODO: Make sure `getLastId` is necessary.
  function getLastId() public view returns (uint) {
    return lastId;
  }

  // TODO: Make sure `getBest` is necessary.
  function getBest(address ofrToken, address reqToken)
    external
    view
    returns (uint)
  {
    requireUnlocked(ofrToken, reqToken);
    return bests[ofrToken][reqToken];
  }

  // Read a particular offer's information.
  function getOfferInfo(
    address ofrToken,
    address reqToken,
    uint offerId,
    bool structured
  ) external view returns (DC.Offer memory, DC.OfferDetail memory) {
    structured; // silence warning about unused variable
    return (offers[ofrToken][reqToken][offerId], offerDetails[offerId]);
  }

  function config() public view returns (DC.Config memory) {
    return IDeployer(DEPLOYER).sauron().config(address(this));
  }

  function deployer() external view returns (IDeployer) {
    return IDeployer(DEPLOYER);
  }

  function getOfferInfo(
    address ofrToken,
    address reqToken,
    uint offerId
  )
    external
    view
    returns (
      bool,
      uint,
      uint,
      uint,
      uint,
      uint,
      uint,
      address
    )
  {
    // TODO: Make sure `requireNoReentrancyLock` is necessary here
    requireUnlocked(ofrToken, reqToken);
    DC.Offer memory offer = offers[ofrToken][reqToken][offerId];
    DC.OfferDetail memory offerDetail = offerDetails[offerId];
    return (
      DC.isOffer(offer),
      offer.wants,
      offer.gives,
      offer.next,
      offerDetail.gasreq,
      offerDetail.gasbase, // global gasbase at offer creation time
      offerDetail.gasprice, // global gasprice at offer creation time
      offerDetail.maker
    );
  }

  //+ignore+TODO low gascost bookkeeping methods
  //+ignore+updateOffer(constant price)
  //+ignore+updateOffer(change price)
}
