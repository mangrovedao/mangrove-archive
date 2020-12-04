// SPDX-License-Identifier: UNLICENSED

/* # Introduction
Due to the 24kB contract size limit, we pay some additional complexity in the form of `DexLib`, to which `Dex` will delegate some calls. It notably includes configuration getters and setters, token transfer low-level functions, as well as the `writeOffer` machinery used by makers when they post new offers and update existing ones.
*/
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "./DexCommon.sol";
import "./interfaces.sol";
import {DexCommon as DC, DexEvents} from "./DexCommon.sol";

library DexLib {
  /* # Token transfer */
  //+clear+
  /*
     `swapTokens` is for the 'normal' mode of operation. It:
     1. Flashloans `takerGives` `REQ_TOKEN` from the taker to the maker and returns false if the loan fails.
     2. Runs `offerDetail.maker`'s `execute` function.
     3. Attempts to send `takerWants` `OFR_TOKEN` from the maker to the taker and reverts if it cannot.
     4. Returns true.
    */

  function swapTokens(
    address ofrToken,
    address reqToken,
    uint offerId,
    uint takerGives,
    uint takerWants,
    DC.OfferDetail memory offerDetail
  ) external returns (bool) {
    if (transferToken(reqToken, msg.sender, offerDetail.maker, takerGives)) {
      // Execute offer
      //uint gr = offerDetail.gasreq;
      //uint g = gasleft();
      //(bool s,) =
      IMaker(offerDetail.maker).execute{gas: offerDetail.gasreq}(
        takerWants,
        takerGives,
        offerDetail.gasprice,
        offerId
      );
      //) {} catch {
      //(bool s,) = address(offerDetail.maker).call{gas:gr}(abi.encodeWithSelector(IMaker.execute.selector,
      //takerWants,
      //takerGives,
      //offerDetail.gasprice,
      //offerId));
      //) {} catch {
      //g = g-gasleft();
      //console.log("gas used",g);
      //}
      require(
        transferToken(ofrToken, offerDetail.maker, msg.sender, takerWants),
        "dex/makerFailToPayTaker"
      );
      return true;
    } else {
      return false;
    }
  }

  /*
     `swapTokens` is for the 'arbitrage' mode of operation. It:
     0. Calls the maker's `execute` function
     1. Flashloans `takerWants` `OFR_TOKEN` from the maker to the taker and reverts if the loan fails.
     2. Runs `msg.sender`'s `execute` function.
     3. Attempts to send `takerGives` `REQ_TOKEN` from the taker to the maker. 
     4. Returns whether the attempt worked.
    */

  function invertedSwapTokens(
    address ofrToken,
    address reqToken,
    uint offerId,
    uint takerGives,
    uint takerWants,
    DC.OfferDetail memory offerDetail
  ) external returns (bool) {
    // Execute offer
    IMaker(offerDetail.maker).execute{gas: offerDetail.gasreq}(
      takerWants,
      takerGives,
      offerDetail.gasprice,
      offerId
    );
    require(
      transferToken(ofrToken, offerDetail.maker, msg.sender, takerWants),
      "dex/makerFailToPayTaker"
    );
    IMaker(msg.sender).execute(
      takerWants,
      takerGives,
      offerDetail.gasprice,
      offerId
    );
    return transferToken(reqToken, msg.sender, offerDetail.maker, takerGives);
  }

  /* `transferToken` is adapted from [existing code](https://soliditydeveloper.com/safe-erc20) and in particular avoids the
  "no return value" bug. It never throws and returns true iff the transfer was successful according to `tokenAddress`. */
  function transferToken(
    address tokenAddress,
    address from,
    address to,
    uint value
  ) internal returns (bool) {
    bytes memory cd =
      abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value);
    (bool success, bytes memory data) = tokenAddress.call(cd);
    return (success && (data.length == 0 || abi.decode(data, (bool))));
  }

  /* # New offer */
  //+clear+

  /* <a id="DexLib/definition/newOffer"></a> When a maker posts a new offer or updates an existing one, the offer gets automatically inserted at the correct location in the book, starting from a maker-supplied `pivotId` parameter. The extra `storage` parameters are sent to `DexLib` by `Dex` so that it can write to `Dex`'s storage. 

  Code in this function is weirdly structured; this is necessary to avoid "stack too deep" errors.

  */
  function writeOffer(
    /* `config`, `freeWei`, `offers`, `offerDetails`, `best` and `offerId` are trusted arguments from `Dex`, while */
    DC.Config memory config,
    mapping(address => uint) storage freeWei,
    mapping(uint => DC.Offer) storage offers,
    mapping(uint => DC.OfferDetail) storage offerDetails,
    DC.UintContainer storage best,
    uint offerId,
    /* `wants`, `gives`, `gasreq`, and `pivotId` are given by `msg.sender`. */
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId,
    bool update
  ) external returns (uint) {
    /* The following checks are first performed: */
    //+clear+
    /* * Check `gasreq` below limit. Implies `gasreq` at most 24 bits wide, which ensures no overflow in computation of `maxPenalty` (see below). */
    require(gasreq <= config.gasmax, "dex/writeOffer/gasreq/tooHigh");
    /* * Make sure that the maker is posting a 'dense enough' offer: the ratio of `OFR_TOKEN` offered per gas consumed must be high enough. The actual gas cost paid by the taker is overapproximated by adding `gasbase` to `gasreq`. Since `gasbase > 0` and `density > 0`, we also get `gives > 0` which protects from future division by 0 and makes the `isLive` method sound. */
    require(
      gives >= (gasreq + config.gasbase * 1000) * config.density,
      "dex/writeOffer/gives/tooLow"
    );

    uint oldPenalty;
    {
      DC.OfferDetail memory offerDetail = offerDetails[offerId];
      if (update) {
        require(
          msg.sender == offerDetail.maker,
          "dex/updateOffer/unauthorized"
        );
        require(
          offerDetail.version + 1 > offerDetail.version,
          "dex/updateOffer/versionOverflow"
        );
        oldPenalty =
          offerDetail.gasprice *
          (uint(offerDetail.gasreq) + offerDetail.gasbase * 1000);
      }

      offerDetails[offerId] = DC.OfferDetail({
        gasreq: uint24(gasreq),
        gasbase: uint8(config.gasbase),
        gasprice: uint48(config.gasprice),
        maker: msg.sender,
        version: update ? offerDetail.version + 1 : 0
      });
    }

    /* With every change to an offer, a maker must deduct provisions from its `freeWei` balance, or get some back if the updated offer requires fewer provisions. */

    {
      uint maxPenalty = (gasreq + config.gasbase * 1000) * config.gasprice;
      if (maxPenalty > oldPenalty) {
        debitWei(freeWei, msg.sender, maxPenalty - oldPenalty);
      } else if (maxPenalty < oldPenalty) {
        creditWei(freeWei, msg.sender, oldPenalty - maxPenalty);
      }
    }

    /* The position of the new or updated offer is found using `findPosition`. If the offer is the best one, `prev == 0`, and if it's the last in the book, `next == 0`.

       `findPosition` is only ever called here, but exists as a separate function to make the code easier to read. */
    (uint prev, uint next) =
      findPosition(offers, best.value, wants, gives, pivotId);

    /* Then we place the offer in the book at the position found by `findPosition`. */
    if (prev != 0) {
      offers[prev].next = uint32(offerId);
    } else {
      best.value = uint32(offerId);
    }

    if (next != 0) {
      offers[next].prev = uint32(offerId);
    }

    /* With the `prev`/`next` in hand, we store the offer in the `offers` and `offerDetails` maps. Note that by `Dex`'s `newOffer` function, `offerId` will always fit in 32 bits. */
    offers[offerId] = DC.Offer({
      prev: uint32(prev),
      next: uint32(next),
      wants: uint96(wants),
      gives: uint96(gives)
    });

    /* And finally return the newly created offer id to the caller. */
    return offerId;
  }

  /* `findPosition` takes a price in the form of a `wants/gives` pair, an offer id (`pivotId`) and walks the book from that offer (backward or forward) until the right position for the price `wants/gives` is found. The position is returned as a `(prev,next)` pair, with `prev` or `next` at 0 to mark the beginning/end of the book (no offer ever has id 0).

  If prices are equal, `findPosition` will put the newest offer last. */
  function findPosition(
    mapping(uint => DC.Offer) storage offers,
    /* As a backup pivot, the id of the current best offer is sent by `Dex` to `DexLib`. This is in case `pivotId` turns out to be an invalid offer id. This part of the code relies on consumed offers being marked as deleted, otherwise we would blindly insert offers next to garbage old values. */
    uint bestValue,
    uint wants,
    uint gives,
    uint pivotId
  ) internal view returns (uint, uint) {
    DC.Offer memory pivot = offers[pivotId];

    if (!DC.isLive(pivot)) {
      // in case pivotId is not or no longer a valid offer
      pivot = offers[bestValue];
      pivotId = bestValue;
    }

    // pivot price better than `wants/gives`, we follow next
    if (better(pivot.wants, pivot.gives, wants, gives)) {
      DC.Offer memory pivotNext;
      while (pivot.next != 0) {
        pivotNext = offers[pivot.next];
        if (better(pivotNext.wants, pivotNext.gives, wants, gives)) {
          pivotId = pivot.next;
          pivot = pivotNext;
        } else {
          break;
        }
      }
      // this is also where we end up with an empty book
      return (pivotId, pivot.next);

      // pivot price strictly worse than `wants/gives`, we follow prev
    } else {
      DC.Offer memory pivotPrev;
      while (pivot.prev != 0) {
        pivotPrev = offers[pivot.prev];
        if (better(pivotPrev.wants, pivotPrev.gives, wants, gives)) {
          break;
        } else {
          pivotId = pivot.prev;
          pivot = pivotPrev;
        }
      }
      return (pivot.prev, pivotId);
    }
  }

  /* The utility method better
    returns false iff the price induced by _(`wants1`,`gives1`)_ is strictly worse than the price induced by _(`wants2`,`gives2`)_. It makes `findPosition` easier to read. */
  function better(
    uint wants1,
    uint gives1,
    uint wants2,
    uint gives2
  ) internal pure returns (bool) {
    return wants1 * gives2 <= wants2 * gives1;
  }

  /* # Maker debit/credit utility functions */

  function debitWei(
    mapping(address => uint) storage freeWei,
    address maker,
    uint amount
  ) internal {
    require(freeWei[maker] >= amount, "dex/insufficientProvision");
    freeWei[maker] -= amount;
    emit DexEvents.Debit(maker, amount);
  }

  function creditWei(
    mapping(address => uint) storage freeWei,
    address maker,
    uint amount
  ) internal {
    freeWei[maker] += amount;
    emit DexEvents.Credit(maker, amount);
  }
}
