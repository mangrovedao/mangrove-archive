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

abstract contract Dex is HasAdmin {
  /* The signature of the low-level swapping function. */
  bytes4 immutable FLASHLOANER;

  uint constant LOCKED = 2;
  uint constant UNLOCKED = 1;

  /* * An offer `id` is defined by two structs, `Offer` and `OfferDetail`, defined in `DexCommon.sol`.
   * `offers[id]` contains pointers to the `prev`ious (better) and `next` (worse) offer in the book, as well as the price and volume of the offer (in the form of two absolute quantities, `wants` and `gives`).
   * `offerDetails[id]` contains the market maker's address (`maker`), the amount of gas required by the offer (`gasreq`) as well cached values for the global `gasbase` and `gasprice` when the offer got created (see `DexCommon` for more on `gasbase` and `gasprice`).
   */
  mapping(address => mapping(address => mapping(uint => bytes32)))
    private offers;
  mapping(address => mapping(address => mapping(uint => bytes32)))
    private offerDetails;

  bytes32 private global;
  mapping(address => mapping(address => bytes32)) private locals;

  /* * Makers provision their possible penalties in the `freeWei` mapping.

       Offers specify the amount of gas they require for successful execution (`gasreq`). To minimize book spamming, market makers must provision a *penalty*, which depends on their `gasreq`. This provision is deducted from their `freeWei`. If an offer fails, part of that provision is given to the taker, as compensation. The exact amount depends on the gas used by the offer before failing.

       The Dex keeps track of their available balance in the `freeWei` map, which is decremented every time a maker creates a new offer (new offer creation is in `DexLib`, see `writeOffer`), and modified on offer updates/cancelations/takings.
   */
  mapping(address => uint) private freeWei;

  /* * `lastId` is a counter for offer ids, incremented every time a new offer is created. It can't go above 2^24-1. */
  mapping(address => mapping(address => uint)) private lastId;

  /* * If `reentrancyLock` is > 1, orders may not be added nor executed.

       Reentrancy during offer execution is not considered safe:
       * during execution, an offer could consume other offers further up in the book, effectively frontrunning the taker currently executing the offer.
       * it could also cancel other offers, creating a discrepancy between the advertised and actual market price at no cost to the maker.
       * an offer insertion consumes an unbounded amount of gas (because it has to be correctly placed in the book).

       Note: An optimization in the `marketOrder` function relies on reentrancy being forbidden.
   */
  mapping(address => mapping(address => uint)) private locks;

  /* `best` is a struct with a single field holding the current best offer id. The id is wrapped in a struct so it can be passed to `DexLib`. */
  mapping(address => mapping(address => uint)) public bests;

  /*
  # Dex Constructor

  A new Dex instance manages one side of a book; it offers `OFR_TOKEN` in return for `REQ_TOKEN`. To initialize a new instance, the deployer must provide initial configuration (see `DexCommon.sol` for more on configuration parameters):
  */
  constructor(
    uint gasprice,
    uint gasbase,
    uint gasmax,
    /* determines whether the taker or maker does the flashlend */
    bool takerLends
  ) HasAdmin() {
    emit DexEvents.NewDex();
    setGasprice(gasprice);
    setGasbase(gasbase);
    setGasmax(gasmax);
    /* In a 'normal' mode of operation, takers lend the liquidity to the maker. */
    /* In an 'arbitrage' mode of operation, takers come ask the makers for liquidity. */
    FLASHLOANER = takerLends
      ? DexLib.flashloan.selector
      : DexLib.invertedFlashloan.selector;
  }

  /*
  # Gatekeeping

  Gatekeeping functions start with `require` and are safety checks called in various places.
  */

  /* `requireNoReentrancyLock` protects modifying the book while an order is in progress. */
  function unlockedOnly(address base, address quote) internal view {
    require(locks[base][quote] < LOCKED, "dex/reentrancyLocked");
  }

  /* * <a id="Dex/definition/requireLiveDex"></a>
     In case of emergency, the Dex can be `kill()`ed. It cannot be resurrected. When a Dex is dead, the following operations are disabled :
       * Executing an offer
       * Sending ETH to the Dex (the normal way, usual shenanigans are possible)
       * Creating a new offerX
   */
  function requireLiveDex(bytes32 _global) internal pure {
    require($$(glo_dead("_global")) == 0, "dex/dead");
  }

  /* TODO documentation */
  function requireActiveMarket(bytes32 _global, bytes32 _local) internal pure {
    requireLiveDex(_global);
    require($$(loc_active("_local")) > 0, "dex/inactive");
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
    address base,
    address quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) external returns (uint) {
    unlockedOnly(base, quote);
    DC.OfferPack memory ofp;
    ofp.base = base;
    ofp.quote = quote;
    ofp.wants = wants;
    ofp.gives = gives; // an offer id must never be 0
    ofp.id = ++lastId[base][quote];
    ofp.gasreq = gasreq;
    ofp.gasprice = gasprice;
    ofp.pivotId = pivotId;
    ofp.global = global;
    ofp.local = locals[base][quote];
    require(uint24(ofp.id) == ofp.id, "dex/offerIdOverflow");

    requireActiveMarket(ofp.global, ofp.local);
    return writeOffer(ofp, false);
  }

  /* ## Cancel Offer */
  //+clear+
  /* `cancelOffer` with `erase == false` takes the offer out of the book. However, `erase == true` clears out the offer's entry in `offers` and `offerDetails` -- an erased offer cannot be resurrected. */
  function cancelOffer(
    address base,
    address quote,
    uint offerId,
    bool erase
  ) external {
    unlockedOnly(base, quote);
    emit DexEvents.CancelOffer(base, quote, offerId, erase);
    bytes32 offer = offers[base][quote][offerId];
    bytes32 offerDetail = offerDetails[base][quote][offerId];
    /* An important invariant is that an offer is 'live' iff (gives > 0) iff (the offer is in the book). Here, we are about to *un-live* the offer, so we start by taking it out of the book. Note that unconditionally calling `stitchOffers` would break the book since it would connect offers that may have moved. */
    require(
      msg.sender == $$(od_maker("offerDetail")),
      "dex/cancelOffer/unauthorized"
    );

    if (isLive(offer)) {
      stitchOffers(base, quote, $$(o_prev("offer")), $$(o_next("offer")));
    }
    if (erase) {
      delete offers[base][quote][offerId];
      delete offerDetails[base][quote][offerId];
    } else {
      dirtyDeleteOffer(base, quote, offerId);
    }

    /* Without a cast to `uint`, the operations convert to the larger type (gasprice) and may truncate */
    uint provision =
      10**9 *
        $$(o_gasprice("offer")) *
        ($$(od_gasreq("offerDetail")) + $$(od_gasbase("offerDetail")));
    creditWei(msg.sender, provision);
  }

  /* ## Update Offer */
  //+clear+
  /* Very similar to `newOffer`, `updateOffer` uses the same code from `DexLib` (`writeOffer`). Makers should use it for updating live offers, but also to save on gas by reusing old, already consumed offers. A pivotId should still be given, to replace the offer at the right book position. It's OK to give the offers' own id as a pivot. */
  function updateOffer(
    address base,
    address quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) public returns (uint) {
    unlockedOnly(base, quote);
    DC.OfferPack memory ofp;
    ofp.base = base;
    ofp.quote = quote;
    ofp.wants = wants;
    ofp.gives = gives;
    ofp.id = offerId;
    ofp.gasreq = gasreq;
    ofp.gasprice = gasprice;
    ofp.pivotId = pivotId;
    ofp.global = global;
    ofp.local = locals[base][quote];
    ofp.oldOffer = offers[base][quote][offerId];
    requireActiveMarket(ofp.global, ofp.local);
    return writeOffer(ofp, true);
  }

  /* ## Provisioning
  Market makers must have enough provisions for possible penalties. These provisions are in ETH. Every time a new offer is created, the `freeWei` balance is decreased by the amount necessary to provision the offer's maximum possible penalty. */
  //+clear+

  /* A transfer with enough gas to the Dex will increase the caller's available `freeWei` balance. _You should send enough gas to execute this function when sending money to the Dex._  */
  function fund(address maker) public payable {
    requireLiveDex(global);
    creditWei(maker, msg.value);
  }

  receive() external payable {
    fund(msg.sender);
  }

  /* The remaining balance of a Maker (excluding the penalties currently locked in pending offers) can read with `balanceOf(address)` and withdrawn with `withdraw(uint)`.*/
  function balanceOf(address maker) external view returns (uint) {
    return freeWei[maker];
  }

  /* Any provision not currently held to secure an offer's possible penalty is available for withdrawal. */
  function withdraw(uint amount) external returns (bool noRevert) {
    /* Since we only ever send money to the caller, we do not need to provide any particular amount of gas, the caller can manage that themselves. Still, as nonzero value calls provide a 2300 gas stipend, a `withdraw(0)` would trigger a call with actual 0 gas. */
    //if (amount == 0) return;
    //+clear+
    debitWei(msg.sender, amount);
    (noRevert, ) = msg.sender.call{gas: 0, value: amount}("");
  }

  /* # Taker operations */
  //+clear+

  /* ## Market Order */
  //+clear+
  /*  `simpleMarketOrder` walks the book and takes offers up to a certain volume of `OFR_TOKEN` and for a maximum average price. */
  function simpleMarketOrder(
    address base,
    address quote,
    uint takerWants,
    uint takerGives
  ) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave, ) = marketOrder(
      base,
      quote,
      takerWants,
      takerGives,
      0,
      bests[base][quote]
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
    address base,
    address quote,
    uint takerWants,
    uint takerGives,
    uint punishLength,
    uint offerId
  )
    public
    returns (
      /* The return value is used for book cleaning: it contains a list (of length `2 * punishLength`) of the offers that failed during the market order, along with the gas they used before failing. */
      uint,
      uint,
      uint[2][] memory
    )
  {
    /* ### Checks */
    //+clear+
    unlockedOnly(base, quote);
    locks[base][quote] = LOCKED;

    /* Since amounts stored in offers are 96 bits wide, checking that `takerWants` fits in 160 bits prevents overflow during the main market order loop. */
    require(uint160(takerWants) == takerWants, "dex/mOrder/takerWants/160bits");
    DC.OrderPack memory orp;
    orp.base = base;
    orp.quote = quote;
    orp.offerId = offerId;
    orp.offer = offers[base][quote][offerId];
    orp.global = global;
    orp.local = locals[base][quote];
    orp.toPunish = new uint[2][](punishLength);
    orp.numToPunish = 0;
    orp.initialWants = takerWants;
    orp.totalGot = 0;
    orp.initialGives = takerGives;
    orp.totalGave = 0;
    orp.wants = 0;
    orp.gives = 0;

    /* For the market order to even start, the market needs to be both alive (that is, not irreversibly killed following emergency action), and not currently protected from reentrancy. */
    requireActiveMarket(orp.global, orp.local);

    /* ### Initialization */
    /* The market order will operate as follows : it will go through offers from best to worse, starting from `offerId`, and: */
    /* * will maintain remaining `takerWants` and `takerGives` values. Their initial ratio is the average price the taker will accept. Better prices may be found early in the book, and worse ones later.
     * will not set `prev`/`next` pointers to their correct locations at each offer taken (this is an optimization enabled by forbidding reentrancy).
     * after consuming a segment of offers, will connect the `prev` and `next` neighbors of the segment's ends.
     * Will maintain an array of pairs `(offerId, gasused)` to identify failed offers. Look at [punishment for failing offers](#dex.sol-punishment-for-failing-offers) for more information. Since there are no extensible in-memory arrays, `punishLength` should be an upper bound on the number of failed offers. */

    /* This check is subtle. We believe the only check that is really necessary here is `offerId != 0`, because any other wrong offerId would point to an empty offer, which would be detected upon division by `offer.gives` in the main loop (triggering a revert). However, with `offerId == 0`, we skip the main loop and try to stitch `pastOfferId` with `offerId`. Basically at this point we're "trusting" `offerId`. This sets `best = 0` and breaks the offer book if it wasn't empty. Out of caution we do a more general check and make sure that the offer exists. The check is an `if` instead of a `require` so we don't throw on an empty market -- but it also means we treat a bad offer id as a take on an empty market. */
    if (isLive(orp.offer)) {
      internalMarketOrder(orp, $$(o_prev("orp.offer")), orp.initialWants != 0);
    }
    return (orp.totalGot, orp.totalGave, orp.toPunish);
  }

  /* ### Main loop */
  //+clear+
  /* Offers are looped through until:
   * remaining amount wanted reaches 0, or
   * `offerId == 0`, which means we've gone past the end of the book. */
  function internalMarketOrder(
    DC.OrderPack memory orp,
    uint pastOfferId,
    bool proceed
  ) internal {
    if (proceed) {
      bool success;
      uint gasLeft;
      /* `executed` is false if offer could not be executed against 2nd and 3rd argument of execute. Currently, we interrupt the loop and let the taker leave with less than they asked for (but at a correct price). We could also revert instead of breaking; this could be a configurable flag for the taker to pick. */
      // reduce stack size for recursion

      bool toDelete;
      orp.wants = orp.initialWants - orp.totalGot;
      orp.gives = orp.initialGives - orp.totalGave;
      orp.offerDetail = offerDetails[orp.base][orp.quote][orp.offerId];

      (success, toDelete, gasLeft) = execute(orp);

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
        By the `Config`, `density * gasbase > 0`, so by the test above `offer.gives - localTakerWants > 0`, so by definition of `localTakerWants`, `localTakerWants == takerWants`. So after updating `takerWants` (the line `takerWants -= localTakerWants`), we have
        ```
         takerWants == 0 < density * gasbase
        ```
        And so the loop ends.
      */

      // those may have been updated by execute, we keep them in stack
      address maker = $$(od_maker("orp.offerDetail"));
      uint offerId = orp.offerId;
      uint takerWants = orp.wants;
      uint takerGives = orp.gives;

      if (toDelete) {
        dirtyDeleteOffer(orp.base, orp.quote, orp.offerId);
        // note that internalMarketOrder may be called twice with same offerId, but in that case proceed will be false!
        orp.offerId = $$(o_next("orp.offer"));
        orp.offer = offers[orp.base][orp.quote][orp.offerId];
      }

      internalMarketOrder(
        orp,
        pastOfferId,
        orp.initialWants - orp.totalGot > 0 && orp.offerId != 0 && toDelete
      );

      // reentrancy is allowed here
      if (success) {
        executeCallback(orp, maker, takerGives); // noop in Classical dex
        makerPosthook(
          orp,
          takerWants,
          takerGives,
          offerId,
          maker,
          toDelete,
          gasLeft
        ); // maker callback
      }
    } else {
      restrictMemoryArrayLength(orp.toPunish, orp.numToPunish);
      stitchOffers(orp.base, orp.quote, pastOfferId, orp.offerId);
      locks[orp.base][orp.quote] = UNLOCKED;
      applyFee(orp);
      executeEnd(orp); //noop if classical Dex
    }
  }

  function makerPosthook(
    DC.OrderPack memory orp,
    uint takerWants,
    uint takerGives,
    uint offerId,
    address maker,
    bool toDelete,
    uint gasLeft
  ) internal {
    IMaker.Posthook memory posthook =
      IMaker.Posthook({
        base: orp.base,
        quote: orp.quote,
        takerWants: takerWants,
        takerGives: takerGives,
        offerId: offerId,
        offerDeleted: toDelete
      });
    bytes memory cd =
      abi.encodeWithSelector(IMaker.makerPosthook.selector, posthook);

    uint oldGas = gasleft();
    if (!(oldGas - oldGas / 64 >= gasLeft)) {
      revert("dex/notEnoughGasForMakerPosthook");
    }
    bool noRevert;
    (noRevert, ) = maker.call{gas: gasLeft}(cd);
  }

  function executeEnd(DC.OrderPack memory orp) internal virtual;

  function executeCallback(
    DC.OrderPack memory orp,
    address maker,
    uint gives
  ) internal virtual;

  /* We could make `execute` part of DexLib to reduce Dex contract size, but we make heavy use of the memory struct `orp` to modify data that will then be used by the caller (`internalSnipes` or `internalMarketOrder`). */
  function execute(DC.OrderPack memory orp)
    internal
    returns (
      bool success,
      bool toDelete,
      uint gasLeft
    )
  {
    /* #### `makerWouldWant` */
    //+clear+
    /* The current offer has a price <code>_p_ = offer.wants/offer.gives</code>. `makerWouldWant` is the amount of `REQ_TOKEN` the offer would require at price _p_ to provide `takerWants` `OFR_TOKEN`. Computing `makeWouldWant` gives us both a test that _p_ is an acceptable price for the taker, and the amount of `REQ_TOKEN` to send to the maker.

    **Note**: We never check that `offerId` is actually a `uint24`, or that `offerId` actually points to an offer: it is not possible to insert an offer with an id larger than that, and a wrong `offerId` will point to a zero-initialized offer, which will revert the call when dividing by `offer.gives`.

   **Note**: Since `takerWants` fits in 160 bits and `offer.wants` fits in 96 bits, the multiplication does not overflow.

   Prices are rounded up. Here is why: offers can be updated. A snipe which names an offer by its id also specifies its price in the form of a `(wants,gives)` pair to be compared to the offers' `(wants,gives)`. See the sniping section for more on why.However, consider an order $r$ for the offer $o$. If $o$ is partially consumed into $o'$ before $r$ is mined, we still want $r$ to succeed (as long as $o'$ has enough volume). But but $o$ wants and give are not $o's$ wants and give. Worse: their ratios are not equal, due to rounding errors.

   Our solution is to make sure that the price of a partially filled offer can only improve. When a snipe can specifies a wants and a gives, it accepts any offer price better than `wants/gives`.

   To do that, we round up the amount required by the maker. That amount will later be deduced from the offer's total volume.
       */
    uint makerWouldWant =
      roundUpRatio(
        orp.wants * $$(o_wants("orp.offer")),
        $$(o_gives("orp.offer"))
      );

    if (makerWouldWant > orp.gives) {
      return (success, toDelete, $$(od_gasreq("orp.offerDetail")));
    }

    /* If the current offer is good enough for the taker can accept, we compute how much the taker should give/get on the _current offer_. So: `takerWants`,`takerGives` are the residual of how much the taker wants to trade overall, while `orp.wants`,`orp.gives` are how much the taker will trade with the current offer. */
    if ($$(o_gives("orp.offer")) < orp.wants) {
      orp.wants = $$(o_gives("orp.offer"));
      orp.gives = $$(o_wants("orp.offer"));
    } else {
      orp.gives = makerWouldWant;
    }

    bool residualBelowDust;
    if (
      $$(o_gives("orp.offer")) - orp.wants <
      $$(loc_density("orp.local")) *
        ($$(od_gasreq("orp.offerDetail")) + $$(glo_gasbase("orp.global")))
    ) {
      residualBelowDust = true;
    }

    /* The flashswap is executed by delegatecall to `FLASHLOANER`. If the call reverts, it means the maker failed to send back `takerWants` `OFR_TOKEN` to the taker. If the call succeeds, `retdata` encodes a boolean indicating whether the taker did send enough to the maker or not.

    Note that any spurious exception due to an error in Dex code will be falsely blamed on the Maker, and its provision for the offer will be unfairly taken away.
    */
    bytes memory retdata;
    (success, retdata) = address(DexLib).delegatecall(
      abi.encodeWithSelector(FLASHLOANER, orp, residualBelowDust)
    );

    uint gasused;

    /* Revert if FLASHLOANER reverted. **Danger**: if a well-crafted offer/maker pair can force a revert of FLASHLOANER, the Dex will be stuck. */
    if (success) {
      gasused = abi.decode(retdata, (uint));

      emit DexEvents.Success(
        orp.base,
        orp.quote,
        orp.offerId,
        orp.wants,
        orp.gives
      );
      orp.totalGot += orp.wants;
      orp.totalGave += orp.gives;

      if (residualBelowDust) {
        toDelete = true;
      } else {
        bytes32 updatedOffer = orp.offer;
        uint newGives = $$(o_gives("updatedOffer")) - orp.wants;
        uint newWants = $$(o_wants("updatedOffer")) - orp.gives;
        offers[orp.base][orp.quote][orp.offerId] = $$(
          o_set("updatedOffer", [["gives", "newGives"], ["wants", "newWants"]])
        );
      }
    } else {
      /* This short reason string should not be exploitable by maker/taker! */
      bytes32 errorCode;
      bytes32 makerData;
      (errorCode, gasused, makerData) = innerDecode(retdata);
      if (
        errorCode == "dex/makerRevert" || errorCode == "dex/makerTransferFail"
      ) {
        toDelete = true;
        emit DexEvents.MakerFail(
          orp.base,
          orp.quote,
          orp.offerId,
          orp.wants,
          orp.gives,
          errorCode == "dex/makerRevert",
          makerData
        );
        if (orp.numToPunish < orp.toPunish.length) {
          orp.toPunish[orp.numToPunish] = [orp.offerId, gasused];
          orp.numToPunish++;
        }
      } else if (errorCode == "dex/tradeOverflow") {
        revert("dex/tradeOverflow");
      } else if (errorCode == "dex/notEnoughGasForMakerTrade") {
        revert("dex/notEnoughGasForMakerTrade");
      } else if (errorCode == "dex/takerFailToPayMaker") {
        revert("dex/takerFailToPayMaker");
      } else {
        revert("dex/swapError");
      }
    }

    gasLeft = $$(od_gasreq("orp.offerDetail")) - gasused;
    applyPenalty(
      success,
      $$(glo_gasprice("orp.global")),
      $$(glo_gasbase("orp.global")),
      gasused,
      orp.offer,
      orp.offerDetail
    );
  }

  function innerDecode(bytes memory data)
    internal
    pure
    returns (
      bytes32 errorCode,
      uint gasused,
      bytes32 makerData
    )
  {
    assembly {
      errorCode := mload(add(data, 32))
      gasused := mload(add(data, 64))
      makerData := mload(add(data, 96))
    }
  }

  /* ## Sniping */
  //+clear+
  /* `snipe` takes a single offer from the book, at whatever price is induced by the offer. */

  function snipe(
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint gasreq
  )
    external
    returns (
      bool,
      uint,
      uint
    )
  {
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [offerId, takerWants, takerGives, gasreq];
    (uint successes, uint takerGot, uint takerGave, ) =
      snipes(base, quote, targets, 1);
    return (successes == 1, takerGot, takerGave);
  }

  //+clear+
  /*
     From an array of _n_ `(offerId, takerWants,takerGives,gasreq)` pairs (encoded as a `uint[2][]` of size _2n_)
     execute each snipe in sequence.

     Also accepts an optional `punishLength` (as in
    `marketOrder`). Returns an array of size at most
    twice `punishLength` containing info on failed offers. Only existing offers can fail: if an offerId is invalid, it will just be skipped. **You should probably set `punishLength` to 1.**
      */
  function snipes(
    address base,
    address quote,
    uint[4][] memory targets,
    uint punishLength
  )
    public
    returns (
      uint,
      uint,
      uint,
      uint[2][] memory
    )
  {
    unlockedOnly(base, quote);
    locks[base][quote] = LOCKED;
    /* ### Pre-loop Checks */
    //+clear+
    DC.OrderPack memory orp;
    orp.base = base;
    orp.quote = quote;
    orp.global = global;
    orp.local = locals[base][quote];
    orp.toPunish = new uint[2][](punishLength);
    orp.numToPunish = 0;
    orp.totalGot = 0;
    orp.totalGave = 0;
    orp.wants = 0;
    orp.gives = 0;

    requireActiveMarket(orp.global, orp.local);

    /* ### Main loop */
    //+clear+

    return (
      internalSnipes(orp, targets, 0, 0),
      orp.totalGot,
      orp.totalGave,
      orp.toPunish
    );
  }

  function internalSnipes(
    DC.OrderPack memory orp,
    uint[4][] memory targets,
    uint i,
    uint successes
  ) internal returns (uint) {
    if (i < targets.length) {
      orp.offerId = targets[i][0];
      orp.offer = offers[orp.base][orp.quote][orp.offerId];
      orp.offerDetail = offerDetails[orp.base][orp.quote][orp.offerId];

      bool success;
      uint gasLeft;
      bool toDelete;

      /* If we removed the `isLive` conditional, a single expired or nonexistent offer in `targets` would revert the entire transaction (by the division by `offer.gives` below). If the taker wants the entire order to fail if at least one offer id is invalid, it suffices to set `punishLength > 0` and check the length of the return value. We also check that `gasreq` is not worse than specified. A taker who does not care about `gasreq` can specify any amount larger than $2^{24}-1$. */
      if (
        isLive(orp.offer) && $$(od_gasreq("orp.offerDetail")) <= targets[i][3]
      ) {
        require(
          uint96(targets[i][1]) == targets[i][1],
          "dex/snipes/takerWants/96bits"
        );
        orp.wants = targets[i][1];
        orp.gives = targets[i][2];
        (success, toDelete, gasLeft) = execute(orp);
        if (success) {
          successes += 1;
        }
        if (toDelete) {
          dirtyDeleteOffer(orp.base, orp.quote, orp.offerId);
          stitchOffers(
            orp.base,
            orp.quote,
            $$(o_prev("orp.offer")),
            $$(o_next("orp.offer"))
          );
        }
      }

      address maker = $$(od_maker("orp.offerDetail"));
      uint offerId = orp.offerId;
      uint takerWants = orp.wants;
      uint takerGives = orp.gives;
      successes = internalSnipes(orp, targets, i + 1, successes);

      if (success) {
        executeCallback(orp, maker, takerGives);
        makerPosthook(
          orp,
          takerWants,
          takerGives,
          offerId,
          maker,
          toDelete,
          gasLeft
        );
      }
    } else {
      /* `applyFee` extracts the fee from the taker, proportional to the amount purchased */
      restrictMemoryArrayLength(orp.toPunish, orp.numToPunish);
      locks[orp.base][orp.quote] = UNLOCKED;
      applyFee(orp);
      executeEnd(orp);
    }

    return successes;
  }

  /* The `toPunish` array initially has size `punishLength`. To remember the number of failures actually stored in `toPunish` (which can be strictly less than `punishLength`), we store `numToPunish` in the length field of `toPunish`. This also saves on the amount of memory copied in the return value.

     The line below is hackish though, and we may want to just return a `(uint,uint[2][])` pair.
   */
  function restrictMemoryArrayLength(uint[2][] memory ary, uint length)
    internal
    pure
  {
    assembly {
      mstore(ary, length)
    }
  }

  /* # Low-level offer deletion */
  function dirtyDeleteOffer(
    address base,
    address quote,
    uint offerId
  ) internal {
    emit DexEvents.DeleteOffer(base, quote, offerId);
    bytes32 offer = offers[base][quote][offerId];
    offers[base][quote][offerId] = $$(o_set("offer", [["gives", 0]]));
  }

  /* Post-trade, `applyFee` reaches back into the taker's pocket and extract a fee on the total amount of `OFR_TOKEN` transferred to them. */
  function applyFee(DC.OrderPack memory orp) internal {
    if (orp.totalGot > 0) {
      uint concreteFee = (orp.totalGot * $$(loc_fee("orp.local"))) / 10_000;
      orp.totalGot -= concreteFee;
      bool success =
        DexLib.transferToken(orp.base, msg.sender, admin, concreteFee);
      require(success, "dex/takerFailToPayDex");
    }
  }

  /* ## Penalties */
  //+clear+
  /* After any offer executes, or after calling a punishment function, `applyPenalty` sends part of the provisioned penalty to the maker, and part to the taker. */
  function applyPenalty(
    bool success,
    uint gasprice,
    uint gasbase,
    uint gasused,
    bytes32 offer,
    bytes32 offerDetail
  ) internal {
    /* We set `gasused = min(gasused,gasreq)` since `gasreq < gasused` is possible (e.g. with `gasreq = 0`). */
    if ($$(od_gasreq("offerDetail")) < gasused) {
      gasused = $$(od_gasreq("offerDetail"));
    }

    /*
       Then we apply penalties:

       * If the transaction was a success, we entirely refund the maker and send nothing to the taker.

       * Otherwise, the maker loses the cost of `gasused + gasbase` gas. The gas price is estimated by `gasprice`.

         Note that to create the offer, the maker had to provision for `gasreq + gasbase` gas at a price of `offer.gasprice`. So consider their entire provision and take as much as possible given the current gasprice.

         Note that we do not consider the tx.gasprice.

         Note that `offerDetail.gasbase` and `offer.gasprice` are the values of the Dex parameters `config.gasbase` and `config.gasprice` when the offer was createdd. Without caching, the provision set aside could be insufficient to reimburse the maker (or to compensate the taker).

     */
    uint released =
      10**9 *
        $$(o_gasprice("offer")) *
        ($$(od_gasreq("offerDetail")) + $$(od_gasbase("offerDetail")));

    if (!success) {
      uint toPay = 10**9 * gasprice * (gasused + gasbase);
      if (toPay > released) {
        toPay = released;
      }
      released = released - toPay;
      bool noRevert;
      (noRevert, ) = msg.sender.call{gas: 0, value: toPay}("");
    }

    creditWei($$(od_maker("offerDetail")), released);
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
    address base,
    address quote,
    uint[4][] calldata targets,
    uint punishLength
  ) external {
    /* We do not directly call `snipes` because we want to revert all the offer executions before returning. So we call an intermediate function, `internalPunishingSnipes` (we don't `call` to preserve the calling context, in partiular `msg.sender`). */
    (bool noRevert, bytes memory retdata) =
      address(this).delegatecall(
        abi.encodeWithSelector(
          this.internalPunishingSnipes.selector,
          base,
          quote,
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
      (, , , uint[2][] memory toPunish) =
        abi.decode(retdata, (uint, uint, uint, uint[2][]));
      punish(base, quote, toPunish);
    }
  }

  /* Sandwiched between `punishingSnipes` and `snipes`, the function `internalPunishingSnipes` runs a sequence of snipes, reverts it, and sends up the list of failed offers. If it catches a revert inside `snipes`, it returns normally a `bytes` array with the raw revert data in it. Again, we use `delegatecall` to preseve `msg.sender`. */
  //TODO explain why it's safe to call from outside
  function internalPunishingSnipes(
    address base,
    address quote,
    uint[4][] calldata targets,
    uint punishLength
  ) external returns (bytes memory retdata) {
    bool noRevert;
    (noRevert, retdata) = address(this).delegatecall(
      abi.encodeWithSelector(
        this.snipes.selector,
        base,
        quote,
        targets,
        punishLength
      )
    );

    /*
     * If `snipes` returns normally, then _the sniping **did not** revert_ and `retdata` is an array of failed offers. In that case we revert.
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
    address base,
    address quote,
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
          base,
          quote,
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
      (, , uint[2][] memory toPunish) =
        abi.decode(retdata, (uint, uint, uint[2][]));
      punish(base, quote, toPunish);
    }
  }

  /* Sandwiched between `punishingMarketOrder` and `marketOrder`, the function `internalPunishingMarketOrder` runs a market order, reverts it, and sends up the list of failed offers. If it catches a revert inside `marketOrder`, it returns normally a `bytes` array with the raw revert data in it. Again, we use `delegatecall` to preserve `msg.sender`. */
  function internalPunishingMarketOrder(
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint punishLength
  ) external returns (bytes memory retdata) {
    bool noRevert;
    (noRevert, retdata) = address(this).delegatecall(
      abi.encodeWithSelector(
        this.marketOrder.selector,
        base,
        quote,
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
  /* Given a sequence of `(offerId, gasused)` pairs, `punish` assumes they have failed and
     executes `applyPenalty` on them.  */
  function punish(
    address base,
    address quote,
    uint[2][] memory toPunish
  ) internal {
    uint punishIndex;
    bytes32 _global = global;
    uint gasprice = $$(glo_gasprice("_global"));
    uint gasbase = $$(glo_gasbase("_global"));
    while (punishIndex < toPunish.length) {
      uint id = toPunish[punishIndex][0];
      /* We read `offer` and `offerDetail` before calling `dirtyDeleteOffer`, since after that they will be erased. */
      bytes32 offer = offers[base][quote][id];
      if (isLive(offer)) {
        bytes32 offerDetail = offerDetails[base][quote][id];
        dirtyDeleteOffer(base, quote, id);
        stitchOffers(base, quote, $$(o_prev("offer")), $$(o_next("offer")));
        uint gasused = toPunish[punishIndex][1];
        applyPenalty(false, gasprice, gasbase, gasused, offer, offerDetail);
      }
      punishIndex++;
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
  // TODO: Make sure `getBest` is necessary.
  function getBest(address base, address quote) external view returns (uint) {
    unlockedOnly(base, quote);
    return bests[base][quote];
  }

  // Read a particular offer's information.
  function getOfferInfo(
    address base,
    address quote,
    uint offerId,
    bool structured
  ) external view returns (DC.Offer memory, DC.OfferDetail memory) {
    structured; // silence warning about unused variable
    bytes32 offer = offers[base][quote][offerId];
    DC.Offer memory offerStruct =
      DC.Offer({
        prev: uint24($$(o_prev("offer"))),
        next: uint24($$(o_next("offer"))),
        wants: uint96($$(o_wants("offer"))),
        gives: uint96($$(o_gives("offer"))),
        gasprice: uint16($$(o_gasprice("offer")))
      });

    bytes32 offerDetail = offerDetails[base][quote][offerId];

    DC.OfferDetail memory offerDetailStruct =
      DC.OfferDetail({
        maker: address($$(od_maker("offerDetail"))),
        gasreq: uint24($$(od_gasreq("offerDetail"))),
        gasbase: uint24($$(od_gasbase("offerDetail")))
      });
    return (offerStruct, offerDetailStruct);
  }

  function getOfferInfo(
    address base,
    address quote,
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
    unlockedOnly(base, quote);
    // TODO: Make sure `requireNoReentrancyLock` is necessary here
    bytes32 offer = offers[base][quote][offerId];
    bytes32 offerDetail = offerDetails[base][quote][offerId];
    return (
      isLive(offer),
      $$(o_wants("offer")),
      $$(o_gives("offer")),
      $$(o_next("offer")),
      $$(od_gasreq("offerDetail")),
      $$(od_gasbase("offerDetail")), // global gasbase at offer creation time
      $$(o_gasprice("offer")), // global gasprice at offer creation time
      $$(od_maker("offerDetail"))
    );
  }

  //+ignore+TODO low gascost bookkeeping methods
  //+ignore+updateOffer(constant price)
  //+ignore+updateOffer(change price)
  /* # Configuration */
  /* should not be called internally, would be a huge memory copying waste */
  function config(address base, address quote)
    external
    view
    returns (DC.Config memory ret)
  {
    bytes32 _global = global;
    ret.global = DC.Global({
      gasprice: uint16($$(glo_gasprice("_global"))),
      gasbase: uint24($$(glo_gasbase("_global"))),
      gasmax: uint24($$(glo_gasmax("_global"))),
      dead: $$(glo_dead("global")) > 0
    });
    bytes32 _local = locals[base][quote];
    ret.local = DC.Local({
      active: $$(loc_active("_local")) > 0,
      fee: uint16($$(loc_fee("_local"))),
      density: uint32($$(loc_density("_local")))
    });
  }

  function roundUpRatio(uint num, uint den) internal pure returns (uint) {
    return num / den + (num % den == 0 ? 0 : 1);
  }

  /* # Configuration access */
  //+clear+
  /* Setter functions for configuration, called by `setConfig` which also exists in Dex. Overloaded by the type of the `value` parameter. See `DexCommon.sol` for more on the `config` and `key` parameters. */

  /* ## Locals */
  /* ### `active` */
  function activate(
    address base,
    address quote,
    uint fee,
    uint density
  ) public {
    adminOnly();
    locals[base][quote] = $$(loc_set("locals[base][quote]", [["active", 1]]));
    setFee(base, quote, fee);
    setDensity(base, quote, density);
    emit DexEvents.SetActive(base, quote, true);
  }

  function deactivate(address base, address quote) public {
    adminOnly();
    locals[base][quote] = $$(loc_set("locals[base][quote]", [["active", 0]]));
    emit DexEvents.SetActive(base, quote, true);
  }

  /* ### `fee` */
  function setFee(
    address base,
    address quote,
    uint value
  ) public {
    adminOnly();
    /* `fee` is in basis points, i.e. in percents of a percent. */
    require(value <= 500, "dex/config/fee/<=500"); // at most 5%
    locals[base][quote] = $$(
      loc_set("locals[base][quote]", [["fee", "value"]])
    );
    emit DexEvents.SetFee(base, quote, value);
  }

  /* ### `density` */
  function setDensity(
    address base,
    address quote,
    uint value
  ) public {
    adminOnly();
    /* `density > 0` ensures various invariants -- this documentation explains each time how it is relevant. */
    require(value > 0, "dex/config/density/>0");
    /* Checking the size of `density` is necessary to prevent overflow when `density` is used in calculations. */
    require(uint32(value) == value, "dex/config/density/32bits");
    //+clear+
    locals[base][quote] = $$(
      loc_set("locals[base][quote]", [["density", "value"]])
    );
    emit DexEvents.SetDensity(base, quote, value);
  }

  /* ## Globals */
  /* ### `kill` */
  function kill() public {
    adminOnly();
    global = $$(glo_set("global", [["dead", 1]]));
    emit DexEvents.Kill();
  }

  /* ### `gasprice` */
  function setGasprice(uint value) public {
    adminOnly();
    /* Checking the size of `gasprice` is necessary to prevent a) data loss when `gasprice` is copied to an `OfferDetail` struct, and b) overflow when `gasprice` is used in calculations. */
    require(uint16(value) == value, "dex/config/gasprice/16bits");
    //+clear+

    global = $$(glo_set("global", [["gasprice", "value"]]));
    emit DexEvents.SetGasprice(value);
  }

  /* ### `gasbase` */
  function setGasbase(uint value) public {
    adminOnly();
    /* `gasbase > 0` ensures various invariants -- this documentation explains how each time it is relevant */
    require(value > 0, "dex/config/gasbase/>0");
    /* Checking the size of `gasbase` is necessary to prevent a) data loss when `gasbase` is copied to an `OfferDetail` struct, and b) overflow when `gasbase` is used in calculations. */
    require(uint24(value) == value, "dex/config/gasbase/24bits");
    //+clear+
    global = $$(glo_set("global", [["gasbase", "value"]]));
    emit DexEvents.SetGasbase(value);
  }

  /* ### `gasmax` */
  function setGasmax(uint value) public {
    adminOnly();
    /* Since any new `gasreq` is bounded above by `config.gasmax`, this check implies that all offers' `gasreq` is 24 bits wide at most. */
    require(uint24(value) == value, "dex/config/gasmax/24bits");
    //+clear+
    global = $$(glo_set("global", [["gasmax", "value"]]));
    emit DexEvents.SetGasmax(value);
  }

  function writeOffer(DC.OfferPack memory ofp, bool update)
    internal
    returns (uint)
  {
    /* gasprice given by maker will be bounded below by internal gasprice estimate at offer write time. with a large enough overapproximation of the gasprice, the maker can regularly update their offer without updating it */
    if (ofp.gasprice < $$(glo_gasprice("ofp.global"))) {
      ofp.gasprice = $$(glo_gasprice("ofp.global"));
    }

    emit DexEvents.WriteOffer(
      ofp.base,
      ofp.quote,
      msg.sender,
      ofp.wants,
      ofp.gives,
      ofp.gasreq,
      ofp.gasprice,
      ofp.id,
      update
    );

    /* The following checks are first performed: */
    //+clear+
    /* * Check `gasreq` below limit. Implies `gasreq` at most 24 bits wide, which ensures no overflow in computation of `provision` (see below). */
    require(
      ofp.gasreq <= $$(glo_gasmax("ofp.global")),
      "dex/writeOffer/gasreq/tooHigh"
    );
    /* * Make sure that the maker is posting a 'dense enough' offer: the ratio of `OFR_TOKEN` offered per gas consumed must be high enough. The actual gas cost paid by the taker is overapproximated by adding `gasbase` to `gasreq`. Since `gasbase > 0` and `density > 0`, we also get `gives > 0` which protects from future division by 0 and makes the `isLive` method sound. */
    require(
      ofp.gives >=
        (ofp.gasreq + $$(glo_gasbase("ofp.global"))) *
          $$(loc_density("ofp.local")),
      "dex/writeOffer/gives/tooLow"
    );

    /* First, we write the new offerDetails and remember the previous provision (0 by default, for new offers) to balance out maker's `freeWei`. */
    uint oldProvision;
    {
      bytes32 offerDetail = offerDetails[ofp.base][ofp.quote][ofp.id];
      if (update) {
        require(
          msg.sender == $$(od_maker("offerDetail")),
          "dex/updateOffer/unauthorized"
        );
        oldProvision =
          10**9 *
          $$(o_gasprice("ofp.oldOffer")) *
          ($$(od_gasreq("offerDetail")) + $$(od_gasbase("offerDetail")));
      }

      //TODO check that we're using less gas if those values haven't changed
      if (
        /* It is currently not possible for a new offer to fail the 3 last tests, but it may in the future, so we make sure we're semantically correct by checking for `!update`. */
        !update ||
        $$(od_gasreq("offerDetail")) != ofp.gasreq ||
        $$(od_gasbase("offerDetail")) != $$(glo_gasbase("ofp.global"))
      ) {
        uint gasbase = $$(glo_gasbase("ofp.global"));
        offerDetails[ofp.base][ofp.quote][ofp.id] = $$(
          od_set(
            "bytes32(0)",
            [
              ["maker", "uint(msg.sender)"],
              ["gasreq", "ofp.gasreq"],
              ["gasbase", "gasbase"]
            ]
          )
        );
      }
    }

    /* With every change to an offer, a maker must deduct provisions from its `freeWei` balance, or get some back if the updated offer requires fewer provisions. */

    {
      uint provision =
        (ofp.gasreq + $$(glo_gasbase("ofp.global"))) * ofp.gasprice * 10**9;
      if (provision > oldProvision) {
        debitWei(msg.sender, provision - oldProvision);
      } else if (provision < oldProvision) {
        creditWei(msg.sender, oldProvision - provision);
      }
    }

    /* The position of the new or updated offer is found using `findPosition`. If the offer is the best one, `prev == 0`, and if it's the last in the book, `next == 0`.

       `findPosition` is only ever called here, but exists as a separate function to make the code easier to read. */
    (uint prev, uint next) = findPosition(bests[ofp.base][ofp.quote], ofp);
    /* Then we place the offer in the book at the position found by `findPosition`.

       If the offer is not the best one, we update its predecessor; otherwise we update the `best` value. */

    /* tests if offer has moved in the book (or was not already there) if next == ofp.id, then the new offer parameters are strictly better than before but still worse than the old prev. if prev == ofp.id, then the new offer parameters are worse or as good as before but still better than the old next. */
    if (!(next == ofp.id || prev == ofp.id)) {
      if (prev != 0) {
        offers[ofp.base][ofp.quote][prev] = $$(
          o_set("offers[ofp.base][ofp.quote][prev]", [["next", "ofp.id"]])
        );
      } else {
        bests[ofp.base][ofp.quote] = ofp.id;
      }

      /* If the offer is not the last one, we update its successor. */
      if (next != 0) {
        offers[ofp.base][ofp.quote][next] = $$(
          o_set("offers[ofp.base][ofp.quote][next]", [["prev", "ofp.id"]])
        );
      }

      /* An important invariant is that an offer is 'live' iff (gives > 0) iff (the offer is in the book). Here, we are about to *move* the offer, so we start by taking it out of the book. Note that unconditionally calling `stitchOffers` would break the book since it would connect offers that may have moved. A priori, if `writeOffer` is called by `newOffer`, `oldOffer` should be all zeros and thus not live. But that would be assuming a subtle implementation detail of `isLive`, so we add the (currently redundant) check on `update`).
       */
      if (update && isLive(ofp.oldOffer)) {
        stitchOffers(
          ofp.base,
          ofp.quote,
          $$(o_prev("ofp.oldOffer")),
          $$(o_next("ofp.oldOffer"))
        );
      }
    }

    /* With the `prev`/`next` in hand, we store the offer in the `offers` and `offerDetails` maps. Note that by `Dex`'s `newOffer` function, `offerId` will always fit in 24 bits (if there is an update, `offerDetails[offerId]` must be owned by `msg.sender`, os `offerId` has the right width). */
    bytes32 ofr =
      $$(
        o_set(
          "bytes32('')",
          [
            ["prev", "prev"],
            ["next", "next"],
            ["wants", "ofp.wants"],
            ["gives", "ofp.gives"],
            ["gasprice", "ofp.gasprice"]
          ]
        )
      );
    offers[ofp.base][ofp.quote][ofp.id] = ofr;

    /* And finally return the newly created offer id to the caller. */

    return ofp.id;
  }

  /* `findPosition` takes a price in the form of a `wants/gives` pair, an offer id (`pivotId`) and walks the book from that offer (backward or forward) until the right position for the price `wants/gives` is found. The position is returned as a `(prev,next)` pair, with `prev` or `next` at 0 to mark the beginning/end of the book (no offer ever has id 0).

  If prices are equal, `findPosition` will put the newest offer last. */
  function findPosition(
    /* As a backup pivot, the id of the current best offer is sent by `Dex` to `DexLib`. This is in case `pivotId` turns out to be an invalid offer id. This part of the code relies on consumed offers being deleted, otherwise we would blindly insert offers next to garbage old values. */
    uint bestValue,
    DC.OfferPack memory ofp
  ) internal view returns (uint, uint) {
    uint pivotId = ofp.pivotId;
    /* optimize for the case wher pivot info is already known */
    bytes32 pivot =
      pivotId == ofp.id ? ofp.oldOffer : offers[ofp.base][ofp.quote][pivotId];

    if (!isLive(pivot)) {
      // in case pivotId is not or no longer a valid offer
      pivot = offers[ofp.base][ofp.quote][bestValue];
      pivotId = bestValue;
    }

    // pivot better than `wants/gives`, we follow next
    if (better(ofp, pivot, pivotId)) {
      bytes32 pivotNext;
      while ($$(o_next("pivot")) != 0) {
        uint pivotNextId = $$(o_next("pivot"));
        pivotNext = offers[ofp.base][ofp.quote][pivotNextId];
        if (better(ofp, pivotNext, pivotNextId)) {
          pivotId = pivotNextId;
          pivot = pivotNext;
        } else {
          break;
        }
      }
      // this is also where we end up with an empty book
      return (pivotId, $$(o_next("pivot")));

      // pivot strictly worse than `wants/gives`, we follow prev
    } else {
      bytes32 pivotPrev;
      while ($$(o_prev("pivot")) != 0) {
        uint pivotPrevId = $$(o_prev("pivot"));
        pivotPrev = offers[ofp.base][ofp.quote][pivotPrevId];
        if (better(ofp, pivotPrev, pivotPrevId)) {
          break;
        } else {
          pivotId = pivotPrevId;
          pivot = pivotPrev;
        }
      }
      return ($$(o_prev("pivot")), pivotId);
    }
  }

  /* The utility method `better`
    returns false iff the point induced by _(`wants1`,`gives1`,`offerDetails[offerId1].gasreq`)_ is strictly worse than the point induced by _(`wants2`,`gives2`,`gasreq2`)_. It makes `findPosition` easier to read. "Worse" is defined on the lexicographic order $\textrm{price} \times_{\textrm{lex}} \textrm{density}^{-1}$.

    This means that for the same price, offers that deliver more volume per gas are taken first.

    To save gas, instead of giving the `gasreq1` argument directly, we provide a path to it (with `offerDetails` and `offerid1`). If necessary (ie. if the prices `wants1/gives1` and `wants2/gives2` are the same), we spend gas and read `gasreq2`.

  */
  function better(
    DC.OfferPack memory ofp,
    bytes32 offer1,
    //uint wants1,
    //uint gives1,
    uint offerId1
  ) internal view returns (bool) {
    uint wants1 = $$(o_wants("offer1"));
    uint gives1 = $$(o_gives("offer1"));
    if (offerId1 == 0) {
      return false;
    } //happens on empty OB
    uint wants2 = ofp.wants;
    uint gives2 = ofp.gives;
    uint weight1 = wants1 * gives2;
    uint weight2 = wants2 * gives1;
    if (weight1 == weight2) {
      uint gasreq1 =
        $$(od_gasreq("offerDetails[ofp.base][ofp.quote][offerId1]"));
      uint gasreq2 = ofp.gasreq;
      return (gives1 * gasreq2 >= gives2 * gasreq1); //density1 is higher
    } else {
      return weight1 < weight2; //price1 is lower
    }
  }

  /* # Maker debit/credit utility functions */

  function debitWei(address maker, uint amount) internal {
    uint makerFreeWei = freeWei[maker];
    require(makerFreeWei >= amount, "dex/insufficientProvision");
    freeWei[maker] = makerFreeWei - amount;
    emit DexEvents.Debit(maker, amount);
  }

  function creditWei(address maker, uint amount) internal {
    freeWei[maker] += amount;
    emit DexEvents.Credit(maker, amount);
  }

  /* The Dex holds a `uint => Offer` mapping in storage. Offer ids that are not yet assigned or that point to since-deleted offer will point to an uninitialized struct. A common way to check for initialization is to add an `exists` field to the struct. In our case, an invariant of the Dex is: on an existing offer, `offer.gives > 0`. So we just check the `gives` field. */
  /* An important invariant is that an offer is 'live' iff (gives > 0) iff (the offer is in the book). */
  function isLive(bytes32 offer) internal pure returns (bool) {
    return $$(o_gives("offer")) > 0;
  }

  /* Connect the predecessor and sucessor of `id` through their `next`/`prev` pointers. For more on the book structure, see `DexCommon.sol`. This step is not necessary during a market order, so we only call `dirtyDeleteOffer` */
  function stitchOffers(
    address base,
    address quote,
    uint pastId,
    uint futureId
  ) internal {
    if (pastId != 0) {
      offers[base][quote][pastId] = $$(
        o_set("offers[base][quote][pastId]", [["next", "futureId"]])
      );
    } else {
      bests[base][quote] = futureId;
    }

    if (futureId != 0) {
      offers[base][quote][futureId] = $$(
        o_set("offers[base][quote][futureId]", [["prev", "pastId"]])
      );
    }
  }
}

contract FMD is Dex {
  constructor(
    uint gasprice,
    uint gasbase,
    uint gasmax
  ) Dex(gasprice, gasbase, gasmax, true) {}

  function executeEnd(DC.OrderPack memory orp) internal override {}

  function executeCallback(
    DC.OrderPack memory orp,
    address maker,
    uint takerGives
  ) internal override {}
}

contract FTD is Dex {
  constructor(
    uint gasprice,
    uint gasbase,
    uint gasmax
  ) Dex(gasprice, gasbase, gasmax, false) {}

  // execute taker trade
  function executeEnd(DC.OrderPack memory orp) internal override {
    ITaker(msg.sender).takerTrade(
      orp.base,
      orp.quote,
      orp.totalGot,
      orp.totalGave
    );
  }

  /* we use `transferFrom` with takers (instead of `balanceOf` technique) for the following reason :
     * we want the taker to be awaken after all loans have been made
     * 1) so either the taker gets a list of all makers and loops through them to pay back, or
     * 2) we call a new taker method "payback" after returning from each maker call, or
     * 3) we call transferFrom after returning from each maker call
     So :
     1) would mean accumulating a list of all makers, which would make the market order code too complex
     2) is OK, but has an extra CALL cost on top of the token transfer, one for each maker. This is unavoidable anyway when calling makerTrade (since the maker must be able to execute arbitrary code at that moment), but we can skip it here.
     3) is the cheapest, but it has the drawbacks of `transferFrom`: money must end up owned by the taker, and taker needs to `approve` Dex
   */
  function executeCallback(
    DC.OrderPack memory orp,
    address maker,
    uint takerGives
  ) internal override {
    bool success =
      DexLib.transferToken(orp.quote, msg.sender, maker, takerGives);
    require(success, "dex/takerFailToPayMaker");
  }
}
