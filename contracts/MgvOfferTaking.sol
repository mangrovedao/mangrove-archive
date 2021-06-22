// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;
import {
  IERC20,
  MgvEvents,
  IMaker,
  IMgvMonitor,
  MgvLib as ML
} from "./MgvLib.sol";
import {MgvHasOffers} from "./MgvHasOffers.sol";

abstract contract MgvOfferTaking is MgvHasOffers {
  /* # MultiOrder struct */
  /* The `MultiOrder` struct is used by market orders and snipes. Some of its fields are only used by market orders (`initialWants, initialGives`), and `successCount` is only used by snipes. The struct is helpful in decreasing stack use. */
  struct MultiOrder {
    uint initialWants;
    uint initialGives;
    uint totalGot;
    uint totalGave;
    uint totalPenalty;
    address taker;
    uint successCount;
    uint failCount;
  }

  /* # Market Orders */

  /* ## Market Order */
  //+clear+

  /* A market order specifies a (`base`,`quote`) pair, a desired total amount of `base` (`takerWants`), and an available total amount of `quote` (`takerGives`). It returns two `uint`s: the total amount of `base` received and the total amount of `quote` spent.

     The `takerGives/takerWants` ratio induces a maximum average price that the taker is ready to pay across all offers that will be executed during the market order. It is thus possible to execute an offer with a price worse than given as argument to `marketOrder` if some cheaper offers were executed earlier in the market order (to request a specific volume (at any price), set `takerWants` to the amount desired and `takerGives` to max uint).

  The market order stops when `takerWants` units of `base` have been obtained, or when the price has become too high, or when the end of the book has been reached. */
  function marketOrder(
    address base,
    address quote,
    uint takerWants,
    uint takerGives
  ) external returns (uint, uint) {
    return generalMarketOrder(base, quote, takerWants, takerGives, msg.sender);
  }

  /* ## General Market Order */
  //+clear+
  /* General market orders set up the market order with a given `taker` (`msg.sender` in the most common case). Returns `(totalGot, totalGave)`. */
  function generalMarketOrder(
    address base,
    address quote,
    uint takerWants,
    uint takerGives,
    address taker
  ) internal returns (uint, uint) {
    /* Since amounts stored in offers are 96 bits wide, checking that `takerWants` fits in 160 bits prevents overflow during the main market order loop. */
    require(uint160(takerWants) == takerWants, "mgv/mOrder/takerWants/160bits");

    /* `SingleOrder` is defined in `MgvLib.sol` and holds information for ordering the execution of one offer. */
    ML.SingleOrder memory sor;
    sor.base = base;
    sor.quote = quote;
    (sor.global, sor.local) = config(base, quote);
    /* Throughout the execution of the market order, the `sor`'s offer id and other parameters will change. We start with the current best offer id (0 if the book is empty). */
    sor.offerId = $$(local_best("sor.local"));
    sor.offer = offers[base][quote][sor.offerId];
    /* `sor.wants` and `sor.gives` may evolve, but they are initially however much remains in the market order. */
    sor.wants = takerWants;
    sor.gives = takerGives;

    /* `MultiOrder` (defined above) maintains information related to the entire market order. During the order, initial `wants`/`gives` values minus the accumulated amounts traded so far give the amounts that remain to be traded. */
    MultiOrder memory mor;
    mor.initialWants = takerWants;
    mor.initialGives = takerGives;
    mor.taker = taker;

    /* For the market order to even start, the market needs to be both active, and not currently protected from reentrancy. */
    activeMarketOnly(sor.global, sor.local);
    unlockedMarketOnly(sor.local);

    /* ### Initialization */
    /* The market order will operate as follows : it will go through offers from best to worse, starting from `offerId`, and: */
    /* * will maintain remaining `takerWants` and `takerGives` values. The initial `takerGives/takerWants` ratio is the average price the taker will accept. Better prices may be found early in the book, and worse ones later.
     * will not set `prev`/`next` pointers to their correct locations at each offer taken (this is an optimization enabled by forbidding reentrancy).
     * after consuming a segment of offers, will update the current `best` offer to be the best remaining offer on the book. */

    /* We start be enabling the reentrancy lock for this (`base`,`quote`) pair. */
    sor.local = $$(set_local("sor.local", [["lock", 1]]));
    locals[base][quote] = sor.local;

    /* `internalMarketOrder` works recursively. Going downward, each successive offer is executed until the market order stops (due to: volume exhausted, bad price, or empty book). Going upward, each offer's `maker` contract is called again with its remaining gas and given the chance to update its offers on the book.

    The last argument is a boolean named `proceed`. If an offer was not executed, it means the price has become too high. In that case, we notify the next recursive call that the market order should end. In this initial call, no offer has been executed yet so `proceed` is true. */
    internalMarketOrder(mor, sor, true);

    /* Over the course of the market order, a penalty reserved for `msg.sender` has accumulated in `mor.totalPenalty`. No actual transfers have occured yet -- all the ethers given by the makers as provision are owned by the Mangrove. `sendPenalty` finally gives the accumulated penalty to `msg.sender`. */
    sendPenalty(mor.totalPenalty);
    //+clear+
    return (mor.totalGot, mor.totalGave);
  }

  /* ## Internal market order */
  //+clear+
  function internalMarketOrder(
    MultiOrder memory mor,
    ML.SingleOrder memory sor,
    bool proceed
  ) internal {
    /* #### Case 1 : End of order */
    /* We execute the offer currently stored in `sor`. */
    if (proceed && sor.wants > 0 && sor.offerId > 0) {
      bool success; // execution success/failure
      uint gasused; // gas used by `makerTrade`
      bytes32 makerData; // data returned by maker
      bytes32 errorCode; // internal Mangrove error code
      /* `executed` is false if offer could not be executed against 2nd and 3rd argument of execute. Currently, we interrupt the loop and let the taker leave with less than they asked for (but at a correct price). We could also revert instead of breaking; this could be a configurable flag for the taker to pick. */

      bool executed; // offer execution attempted or not

      /* Load additional information about the offer. We don't do it earlier to save one storage read in case `proceed` was false. */
      sor.offerDetail = offerDetails[sor.base][sor.quote][sor.offerId];

      /* `execute` will adjust `sor.wants`,`sor.gives`, and may attempt to execute the offer if its price is low enough. It is crucial that an error due to `taker` triggers a revert. That way, `!success && !executed` means there was no execution attempt, and `!success && executed` means the failure is the maker's fault. */
      /* Post-execution, `sor.wants`/`sor.gives` reflect how much was sent/taken by the offer. We will need it after the recursive call, so we save it in local variables. Same goes for `offerId`, `sor.offer` and `sor.offerDetail`. */

      (success, executed, gasused, makerData, errorCode) = execute(mor, sor);

      /* Keep cached copy of current `sor` values. */
      uint takerWants = sor.wants;
      uint takerGives = sor.gives;
      uint offerId = sor.offerId;
      bytes32 offer = sor.offer;
      bytes32 offerDetail = sor.offerDetail;

      /* If an execution was attempted, we move `sor` to the next offer. Note that the current state is inconsistent, since we have not yet updated `sor.offerDetails`. */
      if (executed) {
        /* It is known statically that `mor.initialWants - mor.totalGot` does not underflow since
      1. `mor.totalGot` was increased by `sor.wants` during `execute`,
      2. `sor.wants` was at most `mor.initialWants - mor.totalGot` from earlier step,
      3. `sor.wants` may be have been clamped _down_ to `offer.gives` during `execute`
      */
        sor.wants = mor.initialWants - mor.totalGot;
        /* It is known statically that `mor.initialGives - mor.totalGave` does not underflow since
           1. `mor.totalGave` was increase by `sor.gives` during `execute`,
           2. `sor.gives` was at most `mor.initialGives - mor.totalGave` from earlier step,
           3. `sor.gives` may have been clamped _down_ during `execute` (to `makerWouldWant`, cf. code of `execute`).
        */
        sor.gives = mor.initialGives - mor.totalGave;
        sor.offerId = $$(offer_next("sor.offer"));
        sor.offer = offers[sor.base][sor.quote][sor.offerId];
      }

      /* note that internalMarketOrder may be called twice with same offerId, but in that case `proceed` will be false! */
      internalMarketOrder(
        mor,
        sor,
        // `proceed` value for next call
        executed
      );

      /* Restore `sor` values from to before recursive call */
      sor.offerId = offerId;
      sor.wants = takerWants;
      sor.gives = takerGives;
      sor.offer = offer;
      sor.offerDetail = offerDetail;

      /* After an offer execution, we may run callbacks and increase the total penalty. As that part is common to market orders and snipes, it lives in its own `postExecute` function. */
      if (executed) {
        postExecute(mor, sor, success, gasused, makerData, errorCode);
      }
      /* #### Case 2 : End of market order */
      /* If `proceed` is false, the taker has gotten its requested volume, or we have reached the end of the book, we conclude the market order. */
    } else {
      /* During the market order, all executed offers have been removed from the book. We end by stitching together the `best` offer pointer and the new best offer. */
      sor.local = stitchOffers(sor.base, sor.quote, 0, sor.offerId, sor.local);
      /* Now that the market order is over, we can lift the lock on the book. In the same operation we

      * lift the reentrancy lock, and
      * update the storage

      so we are free from out of order storage writes.
      */
      sor.local = $$(set_local("sor.local", [["lock", 0]]));
      locals[sor.base][sor.quote] = sor.local;

      /* `payTakerMinusFees` sends the fee to the vault, proportional to the amount purchased, and gives the rest to the taker */
      payTakerMinusFees(mor, sor);

      /* In an FTD, amounts have been lent by each offer's maker to the taker. We now call the taker. This is a noop in an FMD. */
      executeEnd(mor, sor);
    }
  }

  /* # Sniping */
  /* ## Snipe(s) */
  //+clear+
  /* `snipe` takes a single offer `offerId` from the book. Since offers can be updated, we specify `takerWants`,`takerGives` and `gasreq`, and only execute if the offer price is acceptable and the offer's gasreq does not exceed `gasreq`.

  It is possible to ask for 0, so we return an additional boolean indicating if `offerId` was successfully executed. Note that we do not distinguish further between mismatched arguments/offer fields on the one hand, and an execution failure on the other. Still, a failed offer has to pay a penalty, and ultimately transaction logs explicitly mention execution failures (see `MgvLib.sol`). */

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
    return
      generalSnipe(
        base,
        quote,
        offerId,
        takerWants,
        takerGives,
        gasreq,
        msg.sender
      );
  }

  /* `snipes` executes multiple offers. It takes a `uint[4][]` as last argument, with each array element of the form `[offerId,takerWants,takerGives,gasreq]`. The return parameters are of the form `(successes,totalGot,totalGave)`. */
  function snipes(
    address base,
    address quote,
    uint[4][] memory targets
  )
    external
    returns (
      uint,
      uint,
      uint
    )
  {
    return generalSnipes(base, quote, targets, msg.sender);
  }

  /* ## General Snipe(s) */
  /* A conduit from `snipe` and `snipeFor` to `generalSnipes`. Returns `(success,takerGot,takerGave)`. */
  function generalSnipe(
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint gasreq,
    address taker
  )
    internal
    returns (
      bool,
      uint,
      uint
    )
  {
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [offerId, takerWants, takerGives, gasreq];
    (uint successes, uint takerGot, uint takerGave) =
      generalSnipes(base, quote, targets, taker);
    return (successes == 1, takerGot, takerGave);
  }

  /*
     From an array of _n_ `[offerId, takerWants,takerGives,gasreq]` elements, execute each snipe in sequence. Returns `(successes, takerGot, takerGave)`. */
  function generalSnipes(
    address base,
    address quote,
    uint[4][] memory targets,
    address taker
  )
    internal
    returns (
      uint,
      uint,
      uint
    )
  {
    ML.SingleOrder memory sor;
    sor.base = base;
    sor.quote = quote;
    (sor.global, sor.local) = config(base, quote);

    MultiOrder memory mor;
    mor.taker = taker;

    /* For the snipes to even start, the market needs to be both active and not currently protected from reentrancy. */
    activeMarketOnly(sor.global, sor.local);
    unlockedMarketOnly(sor.local);

    /* ### Main loop */
    //+clear+

    /* We start be enabling the reentrancy lock for this (`base`,`quote`) pair. */
    sor.local = $$(set_local("sor.local", [["lock", 1]]));
    locals[base][quote] = sor.local;

    /* `internalSnipes` works recursively. Going downward, each successive offer is executed until each snipe in the array has been tried. Going upward, each offer's `maker` contract is called again with its remaining gas and given the chance to update its offers on the book.

    The last argument is the array index for the current offer. It is initially 0. */
    internalSnipes(mor, sor, targets, 0);

    /* Over the course of the snipes order, a penalty reserved for `msg.sender` has accumulated in `mor.totalPenalty`. No actual transfers have occured yet -- all the ethers given by the makers as provision are owned by the Mangrove. `sendPenalty` finally gives the accumulated penalty to `msg.sender`. */
    sendPenalty(mor.totalPenalty);
    //+clear+
    return (mor.successCount, mor.totalGot, mor.totalGave);
  }

  /* ## Internal snipes */
  //+clear+
  function internalSnipes(
    MultiOrder memory mor,
    ML.SingleOrder memory sor,
    uint[4][] memory targets,
    uint i
  ) internal {
    /* #### Case 1 : continuation of snipes */
    if (i < targets.length) {
      sor.offerId = targets[i][0];
      sor.offer = offers[sor.base][sor.quote][sor.offerId];
      sor.offerDetail = offerDetails[sor.base][sor.quote][sor.offerId];

      /* If we removed the `isLive` conditional, a single expired or nonexistent offer in `targets` would revert the entire transaction (by the division by `offer.gives` below since `offer.gives` would be 0). We also check that `gasreq` is not worse than specified. A taker who does not care about `gasreq` can specify any amount larger than $2^{24}-1$. A mismatched price will be detected by `execute`. */
      if (
        !isLive(sor.offer) ||
        $$(offerDetail_gasreq("sor.offerDetail")) > targets[i][3]
      ) {
        /* We move on to the next offer in the array. */
        internalSnipes(mor, sor, targets, i + 1);
      } else {
        bool success;
        uint gasused;
        bool executed;
        bytes32 makerData;
        bytes32 errorCode;

        require(
          uint96(targets[i][1]) == targets[i][1],
          "mgv/snipes/takerWants/96bits"
        );
        sor.wants = targets[i][1];
        sor.gives = targets[i][2];

        /* `execute` will adjust `sor.wants`,`sor.gives`, and may attempt to execute the offer if its price is low enough. It is crucial that an error due to `taker` triggers a revert. That way, `!success && !executed` means there was no execution attempt, and `!success && executed` means the failure is the maker's fault. */
        /* Post-execution, `sor.wants`/`sor.gives` reflect how much was sent/taken by the offer. We will need it after the recursive call, so we save it in local variables. Same goes for `offerId`, `sor.offer` and `sor.offerDetail`. */
        (success, executed, gasused, makerData, errorCode) = execute(mor, sor);

        /* In the market order, we were able to avoid stitching back offers after every `execute` since we knew a continuous segment starting at best would be consumed. Here, we cannot do this optimisation since offers in the `targets` array may be anywhere in the book. So we stitch together offers immediately after each `execute`. */
        if (executed) {
          sor.local = stitchOffers(
            sor.base,
            sor.quote,
            $$(offer_prev("sor.offer")),
            $$(offer_next("sor.offer")),
            sor.local
          );
        }

        {
          /* Keep cached copy of current `sor` values. */
          uint offerId = sor.offerId;
          uint takerWants = sor.wants;
          uint takerGives = sor.gives;
          bytes32 offer = sor.offer;
          bytes32 offerDetail = sor.offerDetail;

          /* We move on to the next offer in the array. */
          internalSnipes(mor, sor, targets, i + 1);

          /* Restore `sor` values from to before recursive call */
          sor.offerId = offerId;
          sor.wants = takerWants;
          sor.gives = takerGives;
          sor.offer = offer;
          sor.offerDetail = offerDetail;
        }

        /* After an offer execution, we may run callbacks and increase the total penalty. As that part is common to market orders and snipes, it lives in its own `postExecute` function. */
        if (executed) {
          postExecute(mor, sor, success, gasused, makerData, errorCode);
        }
      }
      /* #### Case 2 : End of snipes */
    } else {
      /* Now that the snipes is over, we can lift the lock on the book. In the same operation we
      * lift the reentrancy lock, and
      * update the storage

      so we are free from out of order storage writes.
      */
      sor.local = $$(set_local("sor.local", [["lock", 0]]));
      locals[sor.base][sor.quote] = sor.local;
      /* `payTakerMinusFees` sends the fee to the vault, proportional to the amount purchased, and gives the rest to the taker */
      payTakerMinusFees(mor, sor);
      /* In an FTD, amounts have been lent by each offer's maker to the taker. We now call the taker. This is a noop in an FMD. */
      executeEnd(mor, sor);
    }
  }

  /* # General execution */
  /* During a market order or a snipe(s), offers get executed. The following code takes care of executing a single offer with parameters given by a `SingleOrder` within a larger context given by a `MultiOrder`. */

  /* ## Execute */
  /* This function will compare `sor.wants` `sor.gives` with `sor.offer.wants` and `sor.offer.gives`. If the price of the offer is low enough, an execution will be attempted (with volume limited by the offer's advertised volume).

     Summary of the meaning of the return values:
    * `gasused` is the gas consumed by the execution
    * `makerData` is the data returned after executing the offer
    * `errorCode` is the internal Mangrove error code
    * `success -> executed`
    * `success && executed`: offer has succeeded
    * `!success && executed`: offer has failed
    * `!success && !executed`: offer has not been executed */
  function execute(MultiOrder memory mor, ML.SingleOrder memory sor)
    internal
    returns (
      bool success,
      bool executed,
      uint gasused,
      bytes32 makerData,
      bytes32 errorCode
    )
  {
    /* #### `makerWouldWant` */
    //+clear+
    /* The current offer has a price <code>_p_ = sor.offer.wants/sor.offer.gives</code>. `makerWouldWant` is the amount of `quote` the offer would require at price _p_ to provide `sor.wants` `base`. Computing `makeWouldWant` gives us both a test that _p_ is an acceptable price for the taker, and the amount of `quote` to send to the maker.

    **Note**: We never check that `offerId` is actually a `uint24`, or that `offerId` actually points to an offer: it is not possible to insert an offer with an id larger than that, and a wrong `offerId` will point to a zero-initialized offer, which will revert the call when dividing by `offer.gives`.

   Prices are rounded down.
       */
    uint makerWouldWant =
      (sor.wants * $$(offer_wants("sor.offer"))) / $$(offer_gives("sor.offer"));

    /* If the price is too high, we return early. Otherwise we now know we'll execute the offer. */
    if (makerWouldWant > sor.gives) {
      return (false, false, 0, bytes32(0), bytes32(0));
    }

    executed = true;

    /* If the current offer is good enough for the taker can accept, we compute how much the taker should give/get on the _current offer_. So we adjust `sor.wants` and `sor.gives` as follow: if the offer cannot fully satisfy the taker (`sor.offer.gives < sor.wants`), we consume the entire offer. Otherwise `sor.wants` doesn't need to change (the taker will receive everything they wants), and `sor.gives` is adjusted downward to meet the offer's price. */
    if ($$(offer_gives("sor.offer")) < sor.wants) {
      sor.wants = $$(offer_gives("sor.offer"));
      sor.gives = $$(offer_wants("sor.offer"));
    } else {
      sor.gives = makerWouldWant;
    }

    /* The flashloan is executed by call to `flashloan`. If the call reverts, it means the maker failed to send back `sor.wants` `base` to the taker. Notes :
     * `msg.sender` is the Mangrove itself in those calls -- all operations related to the actual caller should be done outside of this call.
     * any spurious exception due to an error in Mangrove code will be falsely blamed on the Maker, and its provision for the offer will be unfairly taken away.
     */
    bytes memory retdata;
    (success, retdata) = address(this).call(
      abi.encodeWithSelector(this.flashloan.selector, sor, mor.taker)
    );

    /* `success` is true: trade is complete */
    if (success) {
      mor.successCount += 1;
      /* In case of success, `retdata` encodes the gas used by the offer. */
      gasused = abi.decode(retdata, (uint));

      emit MgvEvents.Success(
        sor.base,
        sor.quote,
        sor.offerId,
        mor.taker,
        sor.wants,
        sor.gives
      );

      /* If configured to do so, the Mangrove notifies an external contract that a successful trade has taken place. */
      if ($$(global_notify("sor.global")) > 0) {
        IMgvMonitor($$(global_monitor("sor.global"))).notifySuccess(
          sor,
          mor.taker
        );
      }

      /* We update the totals in the multiorder based on the adjusted `sor.wants`/`sor.gives`. */
      mor.totalGot += sor.wants;
      mor.totalGave += sor.gives;
    } else {
      /* In case of failure, `retdata` encodes a short error code, the gas used by the offer, and an arbitrary 256 bits word sent by the maker. `errorCode` should not be exploitable by the maker! */
      (errorCode, gasused, makerData) = innerDecode(retdata);
      /* <a id="MgvOfferTaking/errorCodes"></a> Note that in the `if`s, the literals are bytes32 (stack values), while as revert arguments, they are strings (memory pointers). */
      if (
        errorCode == "mgv/makerRevert" ||
        errorCode == "mgv/makerTransferFail" ||
        errorCode == "mgv/makerReceiveFail"
      ) {
        mor.failCount += 1;

        emit MgvEvents.MakerFail(
          sor.base,
          sor.quote,
          sor.offerId,
          mor.taker,
          sor.wants,
          sor.gives,
          errorCode,
          makerData
        );

        /* If configured to do so, the Mangrove notifies an external contract that a failed trade has taken place. */
        if ($$(global_notify("sor.global")) > 0) {
          IMgvMonitor($$(global_monitor("sor.global"))).notifyFail(
            sor,
            mor.taker
          );
        }
        /* It is crucial that any error code which indicates an error caused by the taker triggers a revert, because functions that call `execute` consider that `execute && !success` should be blamed on the maker. */
      } else if (errorCode == "mgv/notEnoughGasForMakerTrade") {
        revert("mgv/notEnoughGasForMakerTrade");
      } else if (errorCode == "mgv/takerFailToPayMaker") {
        revert("mgv/takerFailToPayMaker");
      } else {
        /* This code must be unreachable. **Danger**: if a well-crafted offer/maker pair can force a revert of `flashloan`, the Mangrove will be stuck. */
        revert("mgv/swapError");
      }
    }

    /* Delete the offer. The last argument indicates whether the offer should be stripped of its provision (yes if execution failed, no otherwise). We delete offers whether the amount remaining on offer is > density or not for the sake of uniformity (code is much simpler). We also expect prices to move often enough that the maker will want to update their price anyway. To simulate leaving the remaining volume in the offer, the maker can program their `makerPosthook` to `updateOffer` and put the remaining volume back in. */
    if (executed) {
      dirtyDeleteOffer(sor.base, sor.quote, sor.offerId, sor.offer, !success);
    }
  }

  /* ## Post execute */
  /* After executing an offer (whether in a market order or in snipes), we
     1. Call the maker's posthook and sum the total gas used.
     3. If offer failed: sum total penalty due to taker and give remainder to maker.
   */
  function postExecute(
    MultiOrder memory mor,
    ML.SingleOrder memory sor,
    bool success,
    uint gasused,
    bytes32 makerData,
    bytes32 errorCode
  ) internal {
    if (success) {
      executeCallback(sor);
    }

    uint gasreq = $$(offerDetail_gasreq("sor.offerDetail"));

    /* We are about to call back the maker, giving it its unused gas (`gasreq - gasused`). Since the gas used so far may exceed `gasreq`, we prevent underflow in the subtraction below by bounding `gasused` above with `gasreq`. We could have decided not to call back the maker at all when there is no gas left, but we do it for uniformity. */
    if (gasused > gasreq) {
      gasused = gasreq;
    }

    gasused =
      gasused +
      makerPosthook(sor, gasreq - gasused, success, makerData, errorCode);

    /* Once again, the gas used may exceed `gasreq`. Since penalties extracted depend on `gasused` and the maker has at most provisioned for `gasreq` being used, we prevent fund leaks by bounding `gasused` once more. */
    if (gasused > gasreq) {
      gasused = gasreq;
    }

    if (!success) {
      mor.totalPenalty += applyPenalty(sor, gasused, mor.failCount);
    }
  }

  /* ## Maker Posthook */
  function makerPosthook(
    ML.SingleOrder memory sor,
    uint gasLeft,
    bool success,
    bytes32 makerData,
    bytes32 errorCode
  ) internal returns (uint gasused) {
    /* At this point, errorCode can only be `"mgv/makerRevert"` or `"mgv/makerTransferFail"` */
    bytes memory cd =
      abi.encodeWithSelector(
        IMaker.makerPosthook.selector,
        sor,
        ML.OrderResult({
          success: success,
          makerData: makerData,
          errorCode: errorCode
        })
      );

    /* Calls an external function with controlled gas expense. A direct call of the form `(,bytes memory retdata) = maker.call{gas}(selector,...args)` enables a griefing attack: the maker uses half its gas to write in its memory, then reverts with that memory segment as argument. After a low-level call, solidity automaticaly copies `returndatasize` bytes of `returndata` into memory. So the total gas consumed to execute a failing offer could exceed `gasreq`. This yul call only retrieves the first 32 bytes of the maker's `returndata`. */
    bytes memory retdata = new bytes(32);

    address maker = $$(offerDetail_maker("sor.offerDetail"));

    uint oldGas = gasleft();
    /* We let the maker pay for the overhead of checking remaining gas and making the call. So the `require` below is just an approximation: if the overhead of (`require` + cost of `CALL`) is $h$, the maker will receive at worst $\textrm{gasreq} - \frac{63h}{64}$ gas. */
    if (!(oldGas - oldGas / 64 >= gasLeft)) {
      revert("mgv/notEnoughGasForMakerPosthook");
    }

    assembly {
      let success2 := call(
        gasLeft,
        maker,
        0,
        add(cd, 32),
        mload(cd),
        add(retdata, 32),
        32
      )
    }
    gasused = oldGas - gasleft();
  }

  /* # Penalties */
  /* Offers are just promises. They can fail. Penalty provisioning discourages from failing too much: we ask makers to provision more ETH than the expected gas cost of executing their offer and penalize them accoridng to wasted gas.

     Under normal circumstances, we should expect to see bots with a profit expectation dry-running offers locally and executing `snipe` on failing offers, collecting the penalty. The result should be a mostly clean book for actual takers (i.e. a book with only successful offers).

     **Incentive issue**: if the gas price increases enough after an offer has been created, there may not be an immediately profitable way to remove the fake offers. In that case, we count on 3 factors to keep the book clean:
     1. Gas price eventually comes down.
     2. Other market makers want to keep the Mangrove attractive and maintain their offer flow.
     3. Mangrove governance (who may collect a fee) wants to keep the Mangrove attractive and maximize exchange volume. */

  //+clear+
  /* After an offer failed, part of its provision is given back to the maker and the rest is stored to be sent to the taker after the entire order completes. In `applyPenalty`, we _only_ credit the maker with its excess provision. So it looks like the maker is gaining something. In fact they're just getting back a fraction of what they provisioned earlier. */
  /*
     Penalty application summary:

   * If the transaction was a success, we entirely refund the maker and send nothing to the taker.
   * Otherwise, the maker loses the cost of `gasused + overhead_gasbase/n + offer_gasbase` gas, where `n` is the number of failed offers. The gas price is estimated by `gasprice`.
   * To create the offer, the maker had to provision for `gasreq + overhead_gasbase/n + offer_gasbase` gas at a price of `offer.gasprice`.
   * We do not consider the tx.gasprice.
   * `offerDetail.gasbase` and `offer.gasprice` are the values of the Mangrove parameters `config.*_gasbase` and `config.gasprice` when the offer was created. Without caching those values, the provision set aside could end up insufficient to reimburse the maker (or to retribute the taker).
   */
  function applyPenalty(
    ML.SingleOrder memory sor,
    uint gasused,
    uint failCount
  ) internal returns (uint) {
    uint provision =
      10**9 *
        $$(offer_gasprice("sor.offer")) *
        ($$(offerDetail_gasreq("sor.offerDetail")) +
          $$(offerDetail_overhead_gasbase("sor.offerDetail")) +
          $$(offerDetail_offer_gasbase("sor.offerDetail")));

    /* We set `gasused = min(gasused,gasreq)` since `gasreq < gasused` is possible e.g. with `gasreq = 0` (all calls consume nonzero gas). */
    if ($$(offerDetail_gasreq("sor.offerDetail")) < gasused) {
      gasused = $$(offerDetail_gasreq("sor.offerDetail"));
    }

    /* As an invariant, `applyPenalty` is only called when `executed && !success`, and thus when `failCount > 0`. */
    uint penalty =
      10**9 *
        $$(global_gasprice("sor.global")) *
        (gasused +
          $$(local_overhead_gasbase("sor.local")) /
          failCount +
          $$(local_offer_gasbase("sor.local")));

    if (penalty > provision) {
      penalty = provision;
    }

    /* Here we write to storage the new maker balance. This occurs _after_ possible reentrant calls. How do we know we're not crediting twice the same amounts? Because the `offer`'s provision was set to 0 in storage (through `dirtyDeleteOffer`) before the reentrant calls. In this function, we are working with cached copies of the offer as it was before it was consumed. */
    creditWei($$(offerDetail_maker("sor.offerDetail")), provision - penalty);

    return penalty;
  }

  function sendPenalty(uint amount) internal {
    if (amount > 0) {
      (bool noRevert, ) = msg.sender.call{value: amount}("");
      require(noRevert, "mgv/sendPenaltyReverted");
    }
  }

  /* Post-trade, `payTakerMinusFees` sends what's due to the taker and the rest (the fees) to the vault. Routing through the Mangrove like that also deals with blacklisting issues (separates the maker-blacklisted and the taker-blacklisted cases). */
  function payTakerMinusFees(MultiOrder memory mor, ML.SingleOrder memory sor)
    internal
  {
    /* Should be statically provable that the 2 transfers below cannot return false under well-behaved ERC20s and a non-blacklisted, non-0 target. */

    uint concreteFee = (mor.totalGot * $$(local_fee("sor.local"))) / 10_000;
    if (concreteFee > 0) {
      mor.totalGot -= concreteFee;
      require(
        transferToken(sor.base, vault, concreteFee),
        "mgv/feeTransferFail"
      );
    }
    if (mor.totalGot > 0) {
      require(
        transferToken(sor.base, mor.taker, mor.totalGot),
        "mgv/MgvFailToPayTaker"
      );
    }
  }

  /* ## Maker Execute */

  function makerExecute(ML.SingleOrder calldata sor)
    internal
    returns (uint gasused)
  {
    bytes memory cd = abi.encodeWithSelector(IMaker.makerTrade.selector, sor);

    /* Calls an external function with controlled gas expense. A direct call of the form `(,bytes memory retdata) = maker.call{gas}(selector,...args)` enables a griefing attack: the maker uses half its gas to write in its memory, then reverts with that memory segment as argument. After a low-level call, solidity automaticaly copies `returndatasize` bytes of `returndata` into memory. So the total gas consumed to execute a failing offer could exceed `gasreq + overhead_gasbase/n + offer_gasbase` where `n` is the number of failing offers. This yul call only retrieves the first byte of the maker's `returndata`. */
    uint gasreq = $$(offerDetail_gasreq("sor.offerDetail"));
    address maker = $$(offerDetail_maker("sor.offerDetail"));
    bytes memory retdata = new bytes(32);
    bool callSuccess;
    bytes32 makerData;
    uint oldGas = gasleft();
    /* We let the maker pay for the overhead of checking remaining gas and making the call. So the `require` below is just an approximation: if the overhead of (`require` + cost of `CALL`) is $h$, the maker will receive at worst $\textrm{gasreq} - \frac{63h}{64}$ gas. */
    /* Note : as a possible future feature, we could stop an order when there's not enough gas left to continue processing offers. This could be done safely by checking, as soon as we start processing an offer, whether `63/64(gasleft-overhead_gasbase-offer_gasbase) > gasreq`. If no, we'd know by induction that there is enough gas left to apply fees, stitch offers, etc (or could revert safely if no offer has been taken yet). */
    if (!(oldGas - oldGas / 64 >= gasreq)) {
      innerRevert([bytes32("mgv/notEnoughGasForMakerTrade"), "", ""]);
    }

    assembly {
      callSuccess := call(
        gasreq,
        maker,
        0,
        add(cd, 32),
        mload(cd),
        add(retdata, 32),
        32
      )
      makerData := mload(add(retdata, 32))
    }
    gasused = oldGas - gasleft();

    if (!callSuccess) {
      innerRevert([bytes32("mgv/makerRevert"), bytes32(gasused), makerData]);
    }

    bool transferSuccess =
      transferTokenFrom(sor.base, maker, address(this), sor.wants);

    if (!transferSuccess) {
      innerRevert(
        [bytes32("mgv/makerTransferFail"), bytes32(gasused), makerData]
      );
    }
  }

  /* ## Misc. functions */

  /* Regular solidity reverts prepend the string argument with a [function signature](https://docs.soliditylang.org/en/v0.7.6/control-structures.html#revert). Since we wish transfer data through a revert, the `innerRevert` function does a low-level revert with only the required data. `innerCode` decodes this data. */
  function innerDecode(bytes memory data)
    internal
    pure
    returns (
      bytes32 errorCode,
      uint gasused,
      bytes32 makerData
    )
  {
    /* The `data` pointer is of the form `[3,errorCode,gasused,makerData]` where each array element is contiguous and has size 256 bits. 3 is added by solidity as the length of the rest of the data. */
    assembly {
      errorCode := mload(add(data, 32))
      gasused := mload(add(data, 64))
      makerData := mload(add(data, 96))
    }
  }

  function innerRevert(bytes32[3] memory data) internal pure {
    assembly {
      revert(data, 96)
    }
  }

  /* `transferTokenFrom` is adapted from [existing code](https://soliditydeveloper.com/safe-erc20) and in particular avoids the
  "no return value" bug. It never throws and returns true iff the transfer was successful according to `tokenAddress`.

    Note that any spurious exception due to an error in Mangrove code will be falsely blamed on `from`.
  */
  function transferTokenFrom(
    address tokenAddress,
    address from,
    address to,
    uint value
  ) internal returns (bool) {
    bytes memory cd =
      abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value);
    (bool noRevert, bytes memory data) = tokenAddress.call(cd);
    return (noRevert && (data.length == 0 || abi.decode(data, (bool))));
  }

  function transferToken(
    address tokenAddress,
    address to,
    uint value
  ) internal returns (bool) {
    bytes memory cd =
      abi.encodeWithSelector(IERC20.transfer.selector, to, value);
    (bool noRevert, bytes memory data) = tokenAddress.call(cd);
    return (noRevert && (data.length == 0 || abi.decode(data, (bool))));
  }

  /* # Abstract functions */

  function flashloan(ML.SingleOrder calldata sor, address taker)
    external
    virtual
    returns (uint gasused);

  function executeEnd(MultiOrder memory mor, ML.SingleOrder memory sor)
    internal
    virtual;

  function executeCallback(ML.SingleOrder memory sor) internal virtual;
}
