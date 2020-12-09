// SPDX-License-Identifier: UNLICENSED

/* # Introduction
Due to the 24kB contract size limit, we pay some additional complexity in the form of `DexLib`, to which `Dex` will delegate some calls. It notably includes configuration getters and setters, token transfer low-level functions, as well as the `newOffer` machinery used by makers when they post new offers.
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
        ofrToken,
        reqToken,
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
      ofrToken,
      reqToken,
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
      ofrToken,
      reqToken,
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

  /* <a id="DexLib/definition/newOffer"></a> When a maker posts a new offer, the offer gets automatically inserted at the correct location in the book, starting from a maker-supplied `pivotId` parameter. The extra `storage` parameters are sent to `DexLib` by `Dex` so that it can write to `Dex`'s storage. */
  function newOffer(
    DC.OfferPack memory ofp,
    mapping(address => uint) storage freeWei,
    mapping(address => mapping(address => mapping(uint => DC.Offer)))
      storage offers,
    mapping(uint => DC.OfferDetail) storage offerDetails,
    mapping(address => mapping(address => uint)) storage bests
  ) external returns (uint) {
    /* The following checks are first performed: */
    //+clear+
    /* * Check `gasreq` below limit. Implies `gasreq` at most 24 bits wide, which ensures no overflow in computation of `maxPenalty` (see below). */
    require(ofp.gasreq <= ofp.config.gasmax, "dex/newOffer/gasreq/tooHigh");
    /* * Make sure that the maker is posting a 'dense enough' offer: the ratio of `OFR_TOKEN` offered per gas consumed must be high enough. The actual gas cost paid by the taker is overapproximated by adding `gasbase` to `gasreq`. Since `gasbase > 0` and `density > 0`, we also get `gives > 0` which protects from future division by 0 and makes the `isOffer` method sound. */
    require(
      ofp.gives >= (ofp.gasreq + ofp.config.gasbase) * ofp.config.density,
      "dex/newOffer/gives/tooLow"
    );
    /* * Unnecessary for safety: check width of `wants`, `gives` and `pivotId`. They will be truncated anyway, but if they are too wide, we assume the maker has made a mistake and revert. */
    require(uint96(ofp.wants) == ofp.wants, "dex/newOffer/wants/96bits");
    require(uint96(ofp.gives) == ofp.gives, "dex/newOffer/gives/96bits");
    require(uint32(ofp.pivotId) == ofp.pivotId, "dex/newOffer/pivotId/32bits");

    /* With every new offer, a maker must deduct provisions from its `freeWei` balance. The maximum penalty is incurred when an offer fails after consuming all its `gasreq`. */

    uint maxPenalty = (ofp.gasreq + ofp.config.gasbase) * ofp.config.gasprice;
    debitWei(freeWei, msg.sender, maxPenalty);

    /* Once provisioned, the position of the new offer is found using `findPosition`. If the offer is the best one, `prev == 0`, and if it's the last in the book, `next == 0`.

       `findPosition` is only ever called here, but exists as a separate function to make the code easier to read. */
    (uint prev, uint next) =
      findPosition(
        offers[ofp.ofrToken][ofp.reqToken],
        offerDetails,
        bests[ofp.ofrToken][ofp.reqToken],
        ofp.wants,
        ofp.gives,
        ofp.gasreq,
        ofp.pivotId
      );
    /* Then we place the offer in the book at the position found by `findPosition`.

       If the offer is not the best one, we update its predecessor; otherwise we update the `best` value. */
    if (prev != 0) {
      offers[ofp.ofrToken][ofp.reqToken][prev].next = uint32(ofp.id);
    } else {
      bests[ofp.ofrToken][ofp.reqToken] = uint32(ofp.id);
    }

    /* If the offer is not the last one, we update its successor. */
    if (next != 0) {
      offers[ofp.ofrToken][ofp.reqToken][next].prev = uint32(ofp.id);
    }

    /* With the `prev`/`next` in hand, we store the offer in the `offers` and `offerDetails` maps. Note that by `Dex`'s `newOffer` function, `offerId` will always fit in 32 bits. */
    offers[ofp.ofrToken][ofp.reqToken][ofp.id] = DC.Offer({
      prev: uint32(prev),
      next: uint32(next),
      wants: uint96(ofp.wants),
      gives: uint96(ofp.gives)
    });

    offerDetails[ofp.id] = DC.OfferDetail({
      gasreq: uint24(ofp.gasreq),
      gasbase: uint24(ofp.config.gasbase),
      gasprice: uint48(ofp.config.gasprice),
      maker: msg.sender
    });

    /* And finally return the newly created offer id to the caller. */
    emit DexEvents.NewOffer(
      ofp.ofrToken,
      ofp.reqToken,
      msg.sender,
      ofp.wants,
      ofp.gives,
      ofp.gasreq,
      ofp.id
    );
    return ofp.id;
  }

  /* `findPosition` takes a price in the form of a `wants/gives` pair, an offer id (`pivotId`) and walks the book from that offer (backward or forward) until the right position for the price `wants/gives` is found. The position is returned as a `(prev,next)` pair, with `prev` or `next` at 0 to mark the beginning/end of the book (no offer ever has id 0).

  If prices are equal, `findPosition` will put the newest offer last. */
  function findPosition(
    mapping(uint => DC.Offer) storage _offers,
    mapping(uint => DC.OfferDetail) storage offerDetails,
    /* As a backup pivot, the id of the current best offer is sent by `Dex` to `DexLib`. This is in case `pivotId` turns out to be an invalid offer id. This part of the code relies on consumed offers being deleted, otherwise we would blindly insert offers next to garbage old values. */
    uint bestValue,
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) internal view returns (uint, uint) {
    DC.Offer memory pivot = _offers[pivotId];

    if (!DC.isOffer(pivot)) {
      // in case pivotId is not or no longer a valid offer
      pivot = _offers[bestValue];
      pivotId = bestValue;
    }

    // pivot better than `wants/gives`, we follow next
    if (
      better(
        offerDetails,
        pivot.wants,
        pivot.gives,
        pivotId,
        wants,
        gives,
        gasreq
      )
    ) {
      DC.Offer memory pivotNext;
      while (pivot.next != 0) {
        pivotNext = _offers[pivot.next];
        if (
          better(
            offerDetails,
            pivotNext.wants,
            pivotNext.gives,
            pivot.next,
            wants,
            gives,
            gasreq
          )
        ) {
          pivotId = pivot.next;
          pivot = pivotNext;
        } else {
          break;
        }
      }
      // this is also where we end up with an empty book
      return (pivotId, pivot.next);

      // pivot strictly worse than `wants/gives`, we follow prev
    } else {
      DC.Offer memory pivotPrev;
      while (pivot.prev != 0) {
        pivotPrev = _offers[pivot.prev];
        if (
          better(
            offerDetails,
            pivotPrev.wants,
            pivotPrev.gives,
            pivot.prev,
            wants,
            gives,
            gasreq
          )
        ) {
          break;
        } else {
          pivotId = pivot.prev;
          pivot = pivotPrev;
        }
      }
      return (pivot.prev, pivotId);
    }
  }

  /* The utility method `better`
    returns false iff the point induced by _(`wants1`,`gives1`,`offerDetails[offerId1].gasreq`)_ is strictly worse than the point induced by _(`wants2`,`gives2`,`gasreq2`)_. It makes `findPosition` easier to read. "Worse" is defined on the lexicographic order $\textrm{price} \times_{\textrm{lex}} \textrm{density}^{-1}$. 

    This means that for the same price, offers that deliver more volume per gas are taken first.

    To save gas, instead of giving the `gasreq1` argument directly, we provide a path to it (with `offerDetails` and `offerid1`). If necessary (ie. if the prices `wants1/gives1` and `wants2/gives2` are the same), we spend gas and read `gasreq2`.

  */
  function better(
    mapping(uint => DC.OfferDetail) storage offerDetails,
    uint wants1,
    uint gives1,
    uint offerId1,
    uint wants2,
    uint gives2,
    uint gasreq2
  ) internal view returns (bool) {
    uint weight1 = wants1 * gives2;
    uint weight2 = wants2 * gives1;
    if (weight1 == weight2) {
      uint gasreq1 = offerDetails[offerId1].gasreq;
      return (gives1 * gasreq2 >= gives2 * gasreq1);
    } else {
      return weight1 < weight2;
    }
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
