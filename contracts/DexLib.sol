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
     3. Returns the result of the operations, with optional makerData to help the maker debug.
   */
  function swapTokens(
    DC.OrderPack calldata orp,
    DC.OfferDetail calldata offerDetail
  )
    external
    returns (
      DC.SwapResult result,
      uint makerData,
      uint gasUsed
    )
  {
    if (transferToken(orp.quote, msg.sender, offerDetail.maker, orp.gives)) {
      //bytes memory cd = abi.encodeWithSelector(IMaker.execute.selector,base,quote,takerWants,takerGives,msg.sender,offerDetail.gasprice,offerId);
      (result, makerData, gasUsed) = makerExecute(orp, offerDetail);
    } else {
      result = DC.SwapResult.TakerTransferFail;
    }
  }

  /*
     `invertedSwapTokens` is for the 'arbitrage' mode of operation. It:
     0. Calls the maker's `execute` function. If successful (tokens have been sent to taker):
     2. Runs `msg.sender`'s `execute` function.
     4. Returns the results ofthe operations, with optional makerData to help the maker debug.
    */

  function invertedSwapTokens(
    DC.OrderPack calldata orp,
    DC.OfferDetail calldata offerDetail
  )
    external
    returns (
      DC.SwapResult result,
      uint makerData,
      uint gasUsed
    )
  {
    (result, makerData, gasUsed) = makerExecute(orp, offerDetail);

    if (result == DC.SwapResult.OK) {
      uint oldBalance = IERC20(orp.quote).balanceOf(offerDetail.maker);

      IMaker(msg.sender).execute(
        orp.base,
        orp.quote,
        orp.wants,
        orp.gives,
        offerDetail.maker,
        offerDetail.gasprice,
        orp.offerId
      );

      uint newBalance = IERC20(orp.quote).balanceOf(offerDetail.maker);
      /* The second check (`newBalance >= oldBalance`) protects against overflow. */
      if (newBalance >= oldBalance + orp.gives && newBalance >= oldBalance) {
        result = DC.SwapResult.OK;
      } else {
        result = DC.SwapResult.TakerTransferFail;
      }
    }
  }

  function makerExecute(
    DC.OrderPack calldata orp,
    //bytes memory cd, address base, uint takerWants,
    DC.OfferDetail calldata offerDetail
  )
    internal
    returns (
      DC.SwapResult result,
      uint makerData,
      uint gasUsed
    )
  {
    bytes memory cd =
      abi.encodeWithSelector(
        IMaker.execute.selector,
        orp.base,
        orp.quote,
        orp.wants,
        orp.gives,
        msg.sender,
        offerDetail.gasprice,
        orp.offerId
      );
    uint oldBalance = IERC20(orp.base).balanceOf(msg.sender);
    /* Calls an external function with controlled gas expense. A direct call of the form `(,bytes memory retdata) = maker.call{gas}(selector,...args)` enables a griefing attack: the maker uses half its gas to write in its memory, then reverts with that memory segment as argument. After a low-level call, solidity automaticaly copies `returndatasize` bytes of `returndata` into memory. So the total gas consumed to execute a failing offer could exceed `gasreq + gasbase`. This yul call only retrieves the first byte of the maker's `returndata`. */
    uint gasreq = offerDetail.gasreq;
    address maker = offerDetail.maker;
    bytes memory retdata = new bytes(32);
    bool success;
    uint oldGas = gasleft();
    assembly {
      success := call(gasreq, maker, 0, add(cd, 32), cd, add(retdata, 32), 32)
      makerData := mload(add(retdata, 32))
    }
    uint newBalance = IERC20(orp.base).balanceOf(msg.sender);
    gasUsed = oldGas - gasleft();
    /* The second check (`newBalance >= oldBalance`) protects against overflow. */
    if (newBalance >= oldBalance + orp.wants && newBalance >= oldBalance) {
      result = DC.SwapResult.OK;
    } else if (!success) {
      result = DC.SwapResult.MakerReverted;
    } else {
      result = DC.SwapResult.MakerTransferFail;
    }
  }

  /* `transferToken` is adapted from [existing code](https://soliditydeveloper.com/safe-erc20) and in particular avoids the
  "no return value" bug. It never throws and returns true iff the transfer was successful according to `tokenAddress`.

    Note that any spurious exception due to an error in Dex code will be falsely blamed on `from`.
  */
  function transferToken(
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

  /* # New offer */
  //+clear+

  /* <a id="DexLib/definition/newOffer"></a> When a maker posts a new offer or updates an existing one, the offer gets automatically inserted at the correct location in the book, starting from a maker-supplied `pivotId` parameter. The extra `storage` parameters are sent to `DexLib` by `Dex` so that it can write to `Dex`'s storage. 

  Code in this function is weirdly structured; this is necessary to avoid "stack too deep" errors.

  */
  function writeOffer(
    DC.OfferPack memory ofp,
    mapping(address => uint) storage freeWei,
    mapping(address => mapping(address => mapping(uint => DC.Offer)))
      storage offers,
    mapping(uint => DC.OfferDetail) storage offerDetails,
    /* The `bests` map is given (instead of current best value) because this function may _write_ a new best value. */
    mapping(address => mapping(address => uint)) storage bests,
    bool update
  ) external returns (uint) {
    /* The following checks are first performed: */
    //+clear+
    /* * Check `gasreq` below limit. Implies `gasreq` at most 24 bits wide, which ensures no overflow in computation of `provision` (see below). */
    require(ofp.gasreq <= ofp.config.gasmax, "dex/writeOffer/gasreq/tooHigh");
    /* * Make sure that the maker is posting a 'dense enough' offer: the ratio of `OFR_TOKEN` offered per gas consumed must be high enough. The actual gas cost paid by the taker is overapproximated by adding `gasbase` to `gasreq`. Since `gasbase > 0` and `density > 0`, we also get `gives > 0` which protects from future division by 0 and makes the `isLive` method sound. */
    require(
      ofp.gives >= (ofp.gasreq + ofp.config.gasbase) * ofp.config.density,
      "dex/writeOffer/gives/tooLow"
    );

    /* First, we write the new offerDetails and remember the previous provision (0 by default, for new offers) to balance out maker's `freeWei`. */
    uint oldProvision;
    {
      DC.OfferDetail memory offerDetail = offerDetails[ofp.id];
      if (update) {
        require(
          msg.sender == offerDetail.maker,
          "dex/updateOffer/unauthorized"
        );
        oldProvision =
          offerDetail.gasprice *
          (uint(offerDetail.gasreq) + offerDetail.gasbase);
      }

      offerDetails[ofp.id] = DC.OfferDetail({
        gasreq: uint24(ofp.gasreq),
        gasbase: uint24(ofp.config.gasbase),
        gasprice: uint48(ofp.config.gasprice),
        maker: msg.sender
      });
    }

    /* With every change to an offer, a maker must deduct provisions from its `freeWei` balance, or get some back if the updated offer requires fewer provisions. */

    {
      uint provision = (ofp.gasreq + ofp.config.gasbase) * ofp.config.gasprice;
      if (provision > oldProvision) {
        debitWei(freeWei, msg.sender, provision - oldProvision);
      } else if (provision < oldProvision) {
        creditWei(freeWei, msg.sender, oldProvision - provision);
      }
    }

    /* The position of the new or updated offer is found using `findPosition`. If the offer is the best one, `prev == 0`, and if it's the last in the book, `next == 0`.

       `findPosition` is only ever called here, but exists as a separate function to make the code easier to read. */
    (uint prev, uint next) =
      findPosition(
        offers[ofp.base][ofp.quote],
        offerDetails,
        bests[ofp.base][ofp.quote],
        ofp
      );
    /* Then we place the offer in the book at the position found by `findPosition`.

       If the offer is not the best one, we update its predecessor; otherwise we update the `best` value. */

    /* tests if offer has moved in the book (or was not already there) if next == ofp.id, then the new offer parameters are strictly better than before but still worse than the old prev. if prev == ofp.id, then the new offer parameters are worse or as good as before but still better than the old next. */
    if (!(next == ofp.id || prev == ofp.id)) {
      if (prev != 0) {
        offers[ofp.base][ofp.quote][prev].next = uint32(ofp.id);
      } else {
        bests[ofp.base][ofp.quote] = uint32(ofp.id);
      }

      /* If the offer is not the last one, we update its successor. */
      if (next != 0) {
        offers[ofp.base][ofp.quote][next].prev = uint32(ofp.id);
      }

      /* An important invariant is that an offer is 'live' iff (gives > 0) iff (the offer is in the book). Here, we are about to *move* the offer, so we start by taking it out of the book. Note that unconditionally calling `stitchOffers` would break the book since it would connect offers that may have moved. A priori, if `writeOffer` is called by `newOffer`, `oldOffer` should be all zeros and thus not live. But that would be assuming a subtle implementation detail of `isLive`, so we add the (currently redundant) check on `update`).
       */
      if (update && DC.isLive(ofp.oldOffer)) {
        DC.stitchOffers(
          ofp.base,
          ofp.quote,
          offers,
          bests,
          ofp.oldOffer.prev,
          ofp.oldOffer.next
        );
      }
    }

    /* With the `prev`/`next` in hand, we store the offer in the `offers` and `offerDetails` maps. Note that by `Dex`'s `newOffer` function, `offerId` will always fit in 32 bits (if there is an update, `offerDetails[offerId]` must be owned by `msg.sender`, os `offerId` has the right width). */
    offers[ofp.base][ofp.quote][ofp.id] = DC.Offer({
      prev: uint32(prev),
      next: uint32(next),
      wants: uint96(ofp.wants),
      gives: uint96(ofp.gives)
    });

    /* And finally return the newly created offer id to the caller. */
    return ofp.id;
  }

  /* `findPosition` takes a price in the form of a `wants/gives` pair, an offer id (`pivotId`) and walks the book from that offer (backward or forward) until the right position for the price `wants/gives` is found. The position is returned as a `(prev,next)` pair, with `prev` or `next` at 0 to mark the beginning/end of the book (no offer ever has id 0).

  If prices are equal, `findPosition` will put the newest offer last. */
  function findPosition(
    mapping(uint => DC.Offer) storage _offers,
    mapping(uint => DC.OfferDetail) storage offerDetails,
    /* As a backup pivot, the id of the current best offer is sent by `Dex` to `DexLib`. This is in case `pivotId` turns out to be an invalid offer id. This part of the code relies on consumed offers being deleted, otherwise we would blindly insert offers next to garbage old values. */
    uint bestValue,
    DC.OfferPack memory ofp
  ) internal view returns (uint, uint) {
    uint pivotId = ofp.pivotId;
    DC.Offer memory pivot = _offers[pivotId];

    if (!DC.isLive(pivot)) {
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
        ofp.wants,
        ofp.gives,
        ofp.gasreq
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
            ofp.wants,
            ofp.gives,
            ofp.gasreq
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
            ofp.wants,
            ofp.gives,
            ofp.gasreq
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
