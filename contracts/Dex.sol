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
  /* The signature of the low-level swapping function. */
  bytes4 immutable SWAPPER;

  uint constant LOCKED = 2;
  uint constant UNLOCKED = 1;

  /* * An offer `id` is defined by two structs, `Offer` and `OfferDetail`, defined in `DexCommon.sol`.
   * `offers[id]` contains pointers to the `prev`ious (better) and `next` (worse) offer in the book, as well as the price and volume of the offer (in the form of two absolute quantities, `wants` and `gives`).
   * `offerDetails[id]` contains the market maker's address (`maker`), the amount of gas required by the offer (`gasreq`) as well cached values for the global `gasbase` and `gasprice` when the offer got created (see `DexCommon` for more on `gasbase` and `gasprice`).
   */
  mapping(address => mapping(address => mapping(uint => DC.Offer)))
    private offers;
  mapping(uint => DC.OfferDetail) private offerDetails;

  /* Configuration. See DexLib for more information. */
  struct Global {
    uint48 gasprice;
    uint24 gasbase;
    uint24 gasmax;
    bool dead;
  }

  struct Local {
    bool active;
    uint16 fee;
    uint32 density;
  }

  Global private global;
  mapping(address => mapping(address => Local)) private locals;

  /* * Makers provision their possible penalties in the `freeWei` mapping.

       Offers specify the amount of gas they require for successful execution (`gasreq`). To minimize book spamming, market makers must provision a *penalty*, which depends on their `gasreq`. This provision is deducted from their `freeWei`. If an offer fails, part of that provision is given to the taker, as compensation. The exact amount depends on the gas used by the offer before failing.

       The Dex keeps track of their available balance in the `freeWei` map, which is decremented every time a maker creates a new offer (new offer creation is in `DexLib`, see `writeOffer`), and modified on offer updates/cancelations/takings.
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
    SWAPPER = takerLends
      ? DexLib.swapTokens.selector
      : DexLib.invertedSwapTokens.selector;
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
  function requireLiveDex(DC.Config memory _config) internal pure {
    require(!_config.dead, "dex/dead");
  }

  /* TODO documentation */
  function requireActiveMarket(DC.Config memory _config) internal pure {
    requireLiveDex(_config);
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
    address base,
    address quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) external returns (uint) {
    unlockedOnly(base, quote);
    DC.Offer memory dummyOffer;
    DC.OfferPack memory ofp =
      DC.OfferPack({
        base: base,
        quote: quote,
        wants: wants,
        gives: gives, // an offer id must never be 0
        id: ++lastId,
        gasreq: gasreq,
        pivotId: pivotId,
        config: config(base, quote),
        oldOffer: dummyOffer
      });
    require(uint32(ofp.id) == ofp.id, "dex/offerIdOverflow");

    requireActiveMarket(ofp.config);
    return DexLib.writeOffer(ofp, freeWei, offers, offerDetails, bests, false);
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
    emit DexEvents.CancelOffer(offerId, erase);
    DC.Offer memory offer = offers[base][quote][offerId];
    DC.OfferDetail memory offerDetail = offerDetails[offerId];
    /* An important invariant is that an offer is 'live' iff (gives > 0) iff (the offer is in the book). Here, we are about to *un-live* the offer, so we start by taking it out of the book. Note that unconditionally calling `stitchOffers` would break the book since it would connect offers that may have moved. */
    require(msg.sender == offerDetail.maker, "dex/cancelOffer/unauthorized");

    if (DC.isLive(offer)) {
      DC.stitchOffers(base, quote, offers, bests, offer.prev, offer.next);
    }
    if (erase) {
      delete offers[base][quote][offerId];
      delete offerDetails[offerId];
    } else {
      dirtyDeleteOffer(base, quote, offerId);
    }

    /* Without a cast to `uint`, the operations convert to the larger type (gasprice) and may truncate */
    uint provision =
      offerDetail.gasprice * (uint(offerDetail.gasreq) + offerDetail.gasbase);
    DexLib.creditWei(freeWei, msg.sender, provision);
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
    uint pivotId,
    uint offerId
  ) public returns (uint) {
    unlockedOnly(base, quote);
    DC.OfferPack memory ofp =
      DC.OfferPack({
        base: base,
        quote: quote,
        wants: wants,
        gives: gives,
        id: offerId,
        gasreq: gasreq,
        pivotId: pivotId,
        config: config(base, quote),
        oldOffer: offers[base][quote][offerId]
      });
    requireActiveMarket(ofp.config);
    return DexLib.writeOffer(ofp, freeWei, offers, offerDetails, bests, true);
  }

  /* ## Provisioning
  Market makers must have enough provisions for possible penalties. These provisions are in ETH. Every time a new offer is created, the `freeWei` balance is decreased by the amount necessary to provision the offer's maximum possible penalty. */
  //+clear+

  /* A transfer with enough gas to the Dex will increase the caller's available `freeWei` balance. _You should send enough gas to execute this function when sending money to the Dex._  */
  receive() external payable {
    requireLiveDex(config(address(0), address(0)));
    DexLib.creditWei(freeWei, msg.sender, msg.value);
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
    DexLib.debitWei(freeWei, msg.sender, amount);
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
  ) external {
    marketOrder(base, quote, takerWants, takerGives, 0, bests[base][quote]);
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
      uint[2][] memory toPunish
    )
  {
    /* ### Checks */
    //+clear+
    unlockedOnly(base, quote);
    locks[base][quote] = LOCKED;

    /* Since amounts stored in offers are 96 bits wide, checking that `takerWants` fits in 160 bits prevents overflow during the main market order loop. */
    require(uint160(takerWants) == takerWants, "dex/mOrder/takerWants/160bits");
    DC.OrderPack memory orp =
      DC.OrderPack({
        base: base,
        quote: quote,
        offerId: offerId,
        offer: offers[base][quote][offerId],
        config: config(base, quote),
        toPunish: new uint[2][](punishLength),
        numToPunish: 0,
        initialWants: takerWants,
        totalGot: 0,
        initialGives: takerGives,
        totalGave: 0
      });

    /* For the market order to even start, the market needs to be both alive (that is, not irreversibly killed following emergency action), and not currently protected from reentrancy. */
    requireActiveMarket(orp.config);

    /* ### Initialization */
    /* The market order will operate as follows : it will go through offers from best to worse, starting from `offerId`, and: */
    /* * will maintain remaining `takerWants` and `takerGives` values. Their initial ratio is the average price the taker will accept. Better prices may be found early in the book, and worse ones later.
     * will not set `prev`/`next` pointers to their correct locations at each offer taken (this is an optimization enabled by forbidding reentrancy).
     * after consuming a segment of offers, will connect the `prev` and `next` neighbors of the segment's ends.
     * Will maintain an array of pairs `(offerId, gasUsed)` to identify failed offers. Look at [punishment for failing offers](#dex.sol-punishment-for-failing-offers) for more information. Since there are no extensible in-memory arrays, `punishLength` should be an upper bound on the number of failed offers. */
    /* This check is subtle. We believe the only check that is really necessary here is `offerId != 0`, because any other wrong offerId would point to an empty offer, which would be detected upon division by `offer.gives` in the main loop (triggering a revert). However, with `offerId == 0`, we skip the main loop and try to stitch `pastOfferId` with `offerId`. Basically at this point we're "trusting" `offerId`. This sets `best = 0` and breaks the offer book if it wasn't empty. Out of caution we do a more general check and make sure that the offer exists. */
    require(DC.isLive(orp.offer), "dex/marketOrder/noSuchOffer");
    uint pastOfferId = orp.offer.prev;

    /* ### Main loop */
    //+clear+
    /* Offers are looped through until:
     * remaining amount wanted reaches 0, or
     * `offerId == 0`, which means we've gone past the end of the book. */
    while (takerWants - orp.totalGot > 0 && orp.offerId != 0) {
      /* `executed` is false if offer could not be executed against 2nd and 3rd argument of executeOrderPack. Currently, we interrupt the loop and let the taker leave with less than they asked for (but at a correct price). We could also revert instead of breaking; this could be a configurable flag for the taker to pick. */
      (, , bool toDelete) =
        executeOrderPack(
          orp,
          orp.initialWants - orp.totalGot,
          orp.initialGives - orp.totalGave
        );

      if (toDelete) {
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
        dirtyDeleteOffer(orp.base, orp.quote, orp.offerId);
        orp.offerId = orp.offer.next;
        orp.offer = offers[orp.base][orp.quote][orp.offerId];
      } else {
        break;
      }
    }

    //if callback maker using recursion: ! warning ! orp now has new values

    applyFee(orp);
    restrictMemoryArrayLength(orp.toPunish, orp.numToPunish);
    DC.stitchOffers(
      orp.base,
      orp.quote,
      offers,
      bests,
      pastOfferId,
      orp.offerId
    );
    toPunish = orp.toPunish;
    locks[base][quote] = UNLOCKED;
  }

  function executeOrderPack(
    DC.OrderPack memory orp,
    uint wants,
    uint gives
  )
    internal
    returns (
      bool executed,
      bool success,
      bool toDelete
    )
  {
    /* #### `makerWouldWant` */
    //+clear+
    /* The current offer has a price <code>_p_ = offer.wants/offer.gives</code>. `makerWouldWant` is the amount of `REQ_TOKEN` the offer would require at price _p_ to provide `takerWants` `OFR_TOKEN`. Computing `makeWouldWant` gives us both a test that _p_ is an acceptable price for the taker, and the amount of `REQ_TOKEN` to send to the maker.

    **Note**: We never check that `offerId` is actually a `uint32`, or that `offerId` actually points to an offer: it is not possible to insert an offer with an id larger than that, and a wrong `offerId` will point to a zero-initialized offer, which will revert the call when dividing by `offer.gives`.

   **Note**: Since `takerWants` fits in 160 bits and `offer.wants` fits in 96 bits, the multiplication does not overflow.

   Prices are rounded up. Here is why: offers can be updated. A snipe which names an offer by its id also specifies its price in the form of a `(wants,gives)` pair to be compared to the offers' `(wants,gives)`. See the sniping section for more on why.However, consider an order $r$ for the offer $o$. If $o$ is partially consumed into $o'$ before $r$ is mined, we still want $r$ to succeed (as long as $o'$ has enough volume). But but $o$ wants and give are not $o's$ wants and give. Worse: their ratios are not equal, due to rounding errors.

   Our solution is to make sure that the price of a partially filled offer can only improve. When a snipe can specifies a wants and a gives, it accepts any offer price better than `wants/gives`.

   To do that, we round up the amount required by the maker. That amount will later be deduced from the offer's total volume.
       */
    uint makerWouldWant =
      roundUpRatio(wants * orp.offer.wants, orp.offer.gives);

    if (makerWouldWant > gives) {
      return (executed, success, toDelete);
    }

    executed = true;

    /* If the current offer is good enough for the taker can accept, we compute how much the taker should give/get on the _current offer_. So: `takerWants`,`takerGives` are the residual of how much the taker wants to trade overall, while `orp.wants`,`orp.gives` are how much the taker will trade with the current offer. */
    if (orp.offer.gives < wants) {
      wants = orp.offer.gives;
      gives = orp.offer.wants;
    } else {
      gives = makerWouldWant;
    }

    DC.OfferDetail memory offerDetail = offerDetails[orp.offerId];

    /* The flashswap is executed by delegatecall to `SWAPPER`. If the call reverts, it means the maker failed to send back `takerWants` `OFR_TOKEN` to the taker. If the call succeeds, `retdata` encodes a boolean indicating whether the taker did send enough to the maker or not.

    Note that any spurious exception due to an error in Dex code will be falsely blamed on the Maker, and its provision for the offer will be unfairly taken away.
    */
    bytes memory retdata;
    (success, retdata) = address(DexLib).delegatecall(
      abi.encodeWithSelector(SWAPPER, orp, offerDetail, wants, gives)
    );

    uint gasUsed;

    /* Revert if SWAPPER reverted. **Danger**: if a well-crafted offer/maker pair can force a revert of SWAPPER, the Dex will be stuck. */
    if (success) {
      gasUsed = abi.decode(retdata, (uint));

      emit DexEvents.Success(orp.offerId, wants, gives);
      orp.totalGot += wants;
      orp.totalGave += gives;

      if (
        orp.offer.gives - wants >=
        orp.config.density * (offerDetail.gasreq + orp.config.gasbase)
      ) {
        offers[orp.base][orp.quote][orp.offerId].gives = uint96(
          orp.offer.gives - wants
        );
        offers[orp.base][orp.quote][orp.offerId].wants = uint96(
          orp.offer.wants - gives
        );
      } else {
        toDelete = true;
      }
    } else {
      /* This short reason string should not be exploitable by maker/taker! */
      bytes32 errorCode;
      bytes32 makerData;
      (errorCode, gasUsed, makerData) = innerDecode(retdata);
      if (
        errorCode == "dex/makerRevert" || errorCode == "dex/makerTransferFail"
      ) {
        toDelete = true;
        emit DexEvents.MakerFail(
          orp.offerId,
          wants,
          gives,
          errorCode == "dex/makerRevert",
          makerData
        );
        if (orp.numToPunish < orp.toPunish.length) {
          orp.toPunish[orp.numToPunish] = [orp.offerId, gasUsed];
          orp.numToPunish++;
        }
      } else if (errorCode == "dex/notEnoughGasForMaker") {
        revert("dex/notEnoughGasForMaker");
      } else if (errorCode == "dex/takerFailToPayMaker") {
        revert("dex/takerFailToPayMaker");
      } else {
        revert("dex/swapError");
      }
    }

    applyPenalty(success, gasUsed, offerDetail);
  }

  function innerDecode(bytes memory data)
    internal
    pure
    returns (
      bytes32 errorCode,
      uint gasUsed,
      bytes32 makerData
    )
  {
    assembly {
      errorCode := mload(add(data, 32))
      gasUsed := mload(add(data, 64))
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
  ) external returns (bool) {
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [offerId, takerWants, takerGives, gasreq];
    (uint successes, ) = internalSnipes(base, quote, targets, 1);
    return (successes == 1);
  }

  //+clear+
  /*
     From an array of _n_ `(offerId, takerWants,takerGives,gasreq)` pairs (encoded as a `uint[2][]` of size _2n_)
     execute each snipe in sequence.

     Also accepts an optional `punishLength` (as in
    `marketOrder`). Returns an array of size at most
    twice `punishLength` containing info on failed offers. Only existing offers can fail: if an offerId is invalid, it will just be skipped. **You should probably set `punishLength` to 1.**
      */
  function internalSnipes(
    address base,
    address quote,
    uint[4][] memory targets,
    uint punishLength
  ) public returns (uint successes, uint[2][] memory toPunish) {
    unlockedOnly(base, quote);
    locks[base][quote] = LOCKED;
    /* ### Pre-loop Checks */
    //+clear+
    DC.OrderPack memory orp;
    orp.base = base;
    orp.quote = quote;
    orp.config = config(base, quote);
    orp.numToPunish = 0;
    orp.toPunish = new uint[2][](punishLength);
    orp.totalGot = 0;
    orp.totalGave = 0;

    requireActiveMarket(orp.config);

    /* ### Main loop */
    //+clear+

    for (uint i = 0; i < targets.length; i++) {
      /* ### In-loop initilization */
      /* targets[i] is [offerId, takerWants, takerGives, gasreq] */
      orp.offerId = targets[i][0];
      orp.offer = offers[orp.base][orp.quote][orp.offerId];
      DC.OfferDetail memory offerDetail = offerDetails[orp.offerId];

      /* If we removed the `isLive` conditional, a single expired or nonexistent offer in `targets` would revert the entire transaction (by the division by `offer.gives` below). If the taker wants the entire order to fail if at least one offer id is invalid, it suffices to set `punishLength > 0` and check the length of the return value. We also check that `gasreq` is not worse than specified. A taker who does not care about `gasreq` can specify any amount larger than $2^{24}-1$. */
      if (DC.isLive(orp.offer) && offerDetail.gasreq <= targets[i][3]) {
        require(
          uint96(targets[i][1]) == targets[i][1],
          "dex/internalSnipes/takerWants/96bits"
        );
        bool success;
        bool toDelete;
        uint wants = targets[i][1];
        uint gives = targets[i][2];
        (, success, toDelete) = executeOrderPack(orp, wants, gives);
        if (success) {
          successes += 1;
        }
        if (toDelete) {
          dirtyDeleteOffer(orp.base, orp.quote, orp.offerId);
          DC.stitchOffers(
            orp.base,
            orp.quote,
            offers,
            bests,
            orp.offer.prev,
            orp.offer.next
          );
        }
      }
    }
    /* `applyFee` extracts the fee from the taker, proportional to the amount purchased */
    applyFee(orp);
    restrictMemoryArrayLength(orp.toPunish, orp.numToPunish);

    toPunish = orp.toPunish;
    locks[base][quote] = UNLOCKED;
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
    emit DexEvents.DeleteOffer(offerId);
    offers[base][quote][offerId].gives = 0;
  }

  /* Post-trade, `applyFee` reaches back into the taker's pocket and extract a fee on the total amount of `OFR_TOKEN` transferred to them. */
  function applyFee(DC.OrderPack memory orp) internal {
    if (orp.totalGot > 0) {
      // amount is at most 160 bits wide and fee it at most 14 bits wide.
      uint concreteFee = (orp.totalGot * orp.config.fee) / 10000;
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
      (, uint[2][] memory toPunish) = abi.decode(retdata, (uint, uint[2][]));
      punish(base, quote, toPunish);
    }
  }

  /* Sandwiched between `punishingSnipes` and `internalSnipes`, the function `internalPunishingSnipes` runs a sequence of snipes, reverts it, and sends up the list of failed offers. If it catches a revert inside `snipes`, it returns normally a `bytes` array with the raw revert data in it. Again, we use `delegatecall` to preseve `msg.sender`. */
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
        this.internalSnipes.selector,
        base,
        quote,
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
      punish(base, quote, abi.decode(retdata, (uint[2][])));
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
  /* Given a sequence of `(offerId, gasUsed)` pairs, `punish` assumes they have failed and
     executes `applyPenalty` on them.  */
  function punish(
    address base,
    address quote,
    uint[2][] memory toPunish
  ) internal {
    uint punishIndex;
    while (punishIndex < toPunish.length) {
      uint id = toPunish[punishIndex][0];
      /* We read `offer` and `offerDetail` before calling `dirtyDeleteOffer`, since after that they will be erased. */
      DC.Offer memory offer = offers[base][quote][id];
      if (DC.isLive(offer)) {
        DC.OfferDetail memory offerDetail = offerDetails[id];
        dirtyDeleteOffer(base, quote, id);
        DC.stitchOffers(base, quote, offers, bests, offer.prev, offer.next);
        uint gasUsed = toPunish[punishIndex][1];
        applyPenalty(false, gasUsed, offerDetail);
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
    return (offers[base][quote][offerId], offerDetails[offerId]);
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
    DC.Offer memory offer = offers[base][quote][offerId];
    DC.OfferDetail memory offerDetail = offerDetails[offerId];
    return (
      DC.isLive(offer),
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
  /* # Configuration */
  function config(address base, address quote)
    public
    view
    returns (DC.Config memory)
  {
    Global memory _global = global;
    Local memory local = locals[base][quote];

    return
      DC.Config({ /* By default, fee is 0, which is fine. */
        dead: _global.dead,
        active: local.active,
        fee: local.fee, /* A density of 0 breaks a Dex, and without a call to `density(value)`, density will be 0. So we return a density of 1 by default. */
        density: local.density == 0 ? 1 : local.density,
        gasprice: _global.gasprice,
        gasbase: _global.gasbase,
        gasmax: _global.gasmax
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
  function setActive(
    address base,
    address quote,
    bool value
  ) public adminOnly {
    locals[base][quote].active = value;
    emit DexEvents.SetActive(base, quote, value);
  }

  /* ### `fee` */
  function setFee(
    address base,
    address quote,
    uint value
  ) public adminOnly {
    /* `fee` is in basis points, i.e. in percents of a percent. */
    require(value <= 500, "dex/config/fee/<=500"); // at most 5%
    locals[base][quote].fee = uint16(value);
    emit DexEvents.SetFee(base, quote, value);
  }

  /* ### `density` */
  function setDensity(
    address base,
    address quote,
    uint value
  ) public adminOnly {
    /* `density > 0` ensures various invariants -- this documentation explains each time how it is relevant. */
    require(value > 0, "dex/config/density/>0");
    /* Checking the size of `density` is necessary to prevent overflow when `density` is used in calculations. */
    require(uint32(value) == value, "dex/config/density/32bits");
    //+clear+
    locals[base][quote].density = uint32(value);
    emit DexEvents.SetDensity(base, quote, value);
  }

  /* ## Globals */
  /* ### `kill` */
  function kill() public adminOnly {
    global.dead = true;
    emit DexEvents.Kill();
  }

  /* ### `gasprice` */
  function setGasprice(uint value) public adminOnly {
    /* Checking the size of `gasprice` is necessary to prevent a) data loss when `gasprice` is copied to an `OfferDetail` struct, and b) overflow when `gasprice` is used in calculations. */
    require(uint48(value) == value, "dex/config/gasprice/48bits");
    //+clear+
    global.gasprice = uint48(value);
    emit DexEvents.SetGasprice(value);
  }

  /* ### `gasbase` */
  function setGasbase(uint value) public adminOnly {
    /* `gasbase > 0` ensures various invariants -- this documentation explains how each time it is relevant */
    require(value > 0, "dex/config/gasbase/>0");
    /* Checking the size of `gasbase` is necessary to prevent a) data loss when `gasbase` is copied to an `OfferDetail` struct, and b) overflow when `gasbase` is used in calculations. */
    require(uint24(value) == value, "dex/config/gasbase/24bits");
    //+clear+
    global.gasbase = uint24(value);
    emit DexEvents.SetGasbase(value);
  }

  /* ### `gasmax` */
  function setGasmax(uint value) public adminOnly {
    /* Since any new `gasreq` is bounded above by `config.gasmax`, this check implies that all offers' `gasreq` is 24 bits wide at most. */
    require(uint24(value) == value, "dex/config/gasmax/24bits");
    //+clear+
    global.gasmax = uint24(value);
    emit DexEvents.SetGasmax(value);
  }
}
