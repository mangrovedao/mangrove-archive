// SPDX-License-Identifier: UNLICENSED

/* # Introduction
Due to the 24kB contract size limit, we pay some additional complexity in the form of `DexLib`, to which `Dex` will delegate some calls. It notably includes configuration getters and setters, token transfer low-level functions, as well as the `newOffer` machinery used by makers when they post new offers.
*/
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "./DexCommon.sol";
import "./interfaces.sol";

library DexLib {
  /* # Configuration access */
  //+clear+
  /* Setter functions for configuration, called by `setConfigKey` which also exists in Dex. Overloaded by the type of the `value` parameter. See `DexCommon.sol` for more on the `config` and `key` parameters. */
  function setConfigKey(
    Config storage config,
    ConfigKey key,
    uint value
  ) external {
    /* Also, for more details on each parameter, see `DexCommon.sol` as well. For the limits on `uint*` sizes, note that while we do store all the following parameters are `uint`s, they will later be stored or used in calculations that must not over/underflow. */
    if (key == ConfigKey.takerFee) {
      require(value <= 10000, "takerFee is in bps, must be <= 10000"); // at most 14 bits
      config.takerFee = value;
      emit DexEvents.SetTakerFee(value);
    } else if (key == ConfigKey.gasOverhead) {
      require(value > 0, "gasOverhead must be > 0");
      require(uint24(value) == value, "gasOverhead is 24 bits wide");
      config.gasOverhead = value;
      emit DexEvents.SetGasOverhead(value);
    } else if (key == ConfigKey.dustPerGasWanted) {
      require(value > 0, "dustPerGasWanted must be > 0");
      require(uint32(value) == value);
      config.dustPerGasWanted = value;
      emit DexEvents.SetDustPerGasWanted(value);
    } else if (key == ConfigKey.penaltyPerGas) {
      require(uint48(value) == value, "penaltyPerGas is 48 bits wide");
      config.penaltyPerGas = value;
      emit DexEvents.SetPenaltyPerGas(value);
    } else if (key == ConfigKey.maxGasWanted) {
      /* Since any new `gasWanted` is bounded above by `config.maxGasWanted`, this check implies that all offers' `gasWanted` is 24 bits wide at most. */
      require(uint24(value) == value, "maxGasWanted is 24 bits wide");
      config.maxGasWanted = value;
      emit DexEvents.SetMaxGasWanted(value);
    } else {
      revert("Unknown config key");
    }
  }

  function setConfigKey(
    Config storage config,
    ConfigKey key,
    address value
  ) external {
    if (key == ConfigKey.admin) {
      config.admin = value;
      emit DexEvents.SetAdmin(value);
    } else {
      revert("Unknown config key");
    }
  }

  function getConfigUint(Config storage config, ConfigKey key)
    external
    view
    returns (uint)
  {
    if (key == ConfigKey.takerFee) {
      return config.takerFee;
    } else if (key == ConfigKey.gasOverhead) {
      return config.gasOverhead;
    } else if (key == ConfigKey.dustPerGasWanted) {
      return config.dustPerGasWanted;
    } else if (key == ConfigKey.penaltyPerGas) {
      return config.penaltyPerGas;
    } else if (key == ConfigKey.maxGasWanted) {
      return config.maxGasWanted;
    } else {
      revert("Unknown config key");
    }
  }

  function getConfigAddress(Config storage config, ConfigKey key)
    external
    view
    returns (address value)
  {
    if (key == ConfigKey.admin) {
      return config.admin;
    } else {
      revert("Unknown config key");
    }
  }

  /* # Token transfer */
  //+clear+
  /* 
   `swapTokens` flashloans `takerGives` `REQ_TOKEN` from the taker to the maker and returns false if the loan fails. It then:
  1. Runs `offerDetail.maker`'s `execute` function.
  2. Attempts to send `takerWants` `OFR_TOKEN` from the maker to the taker and reverts if it cannot.
  3. Returns true.
    */

  function swapTokens(
    address ofrToken,
    address reqToken,
    uint offerId,
    uint takerGives,
    uint takerWants,
    OfferDetail memory offerDetail
  ) external returns (bool) {
    if (transferToken(reqToken, msg.sender, offerDetail.maker, takerGives)) {
      // Execute offer
      IMaker(offerDetail.maker).execute{gas: offerDetail.gasWanted}(
        takerWants,
        takerGives,
        offerDetail.penaltyPerGas,
        offerId
      );

      require(
        transferToken(ofrToken, offerDetail.maker, msg.sender, takerWants),
        "fail transfer to taker"
      );
      return true;
    } else {
      return false;
    }
  }

  /* `transferToken` is adapted from
   `https://soliditydeveloper.com/safe-erc20` and in particular avoids the
  "no return value" bug. It never throws and returns true iff the transfer was successful according to `tokenAddress`. */
  function transferToken(
    address tokenAddress,
    address from,
    address to,
    uint value
  ) internal returns (bool) {
    bytes memory cd = abi.encodeWithSelector(
      IERC20.transferFrom.selector,
      from,
      to,
      value
    );
    (bool success, bytes memory data) = tokenAddress.call(cd);
    return (success && (data.length == 0 || abi.decode(data, (bool))));
  }

  /* # New offer */
  //+clear+

  /* When a maker posts a new offer, the offer gets automatically inserted at the correct location in the book, starting from a maker-supplied `pivotId` parameter. The extra `storage` parameters are sent to `DexLib` by `Dex` so that it can write to `Dex`'s storage. */
  function newOffer(
    /* `config`, `freeWei`, `offers`, `offerDetails`, `best` and `_offerId` are trusted arguments from `Dex`, while */
    Config storage config,
    mapping(address => uint) storage freeWei,
    mapping(uint => Offer) storage offers,
    mapping(uint => OfferDetail) storage offerDetails,
    UintContainer storage best,
    uint offerId,
    /* `wants`, `gives`, `gasWanted`, and `pivotId` are given by `msg.sender`. */
    uint wants,
    uint gives,
    uint gasWanted,
    uint pivotId
  ) external returns (uint) {
    /* The following checks are first performed: */
    //+clear+
    /* * Check `gasWanted` below limit. Implies `gasWanted` at most 24 bits wide, which ensures no overflow in computation of `maxPenalty` (see below). */
    require(gasWanted <= config.maxGasWanted, "gasWanted too large");
    /* Check `gasWanted` above absolute limit. There is an overhead associated with executing an offer, and that overhead is paid for by the maker only when the offer fails. Without an absolute gasWanted limit */
    require(gasWanted > 0, "gasWanted > 0");
    /* * Make sure that the maker is posting a 'dense enough' offer: the ratio of `OFR_TOKEN` offered per gas consumed must be high enough. The actual gas cost paid by the taker is overapproximated by adding `gasOverhead` to `gasWanted`. Since `gasOverhead > 0` and `dustPerGasWanted > 0`, we also get `gives > 0` which protects from future division by 0 and makes the `isOffer` method sound. */
    require(
      gives >= (gasWanted + config.gasOverhead) * config.dustPerGasWanted,
      "offering below dust limit"
    );
    /* * Unnecessary for safety: check width of `wants`, `gives` and `pivotId`. They will be truncated anyway, but if they are too wide, we assume the maker has made a mistake and revert. */
    require(uint96(wants) == wants, "wants is 96 bits wide");
    require(uint96(gives) == gives, "wants is 96 bits wide");
    require(uint32(pivotId) == pivotId, "pivotId is 32 bits wide");

    /* With every new offer, a maker must deduct provisions from its `freeWei` balance. The maximum penalty is incurred when an offer fails after consuming all its `gasWanted`. */
    {
      uint maxPenalty = (gasWanted + config.gasOverhead) * config.penaltyPerGas;
      debitWei(freeWei, msg.sender, maxPenalty);
    }

    /* Once provisioned, the position of the new offer is found using `findPosition`. If the offer is the best one, `prev == 0`, and if it's the last in the book, `next == 0`.

       `findPosition` is only ever called here, but exists as a separate function to make the code easier to read. */
    (uint prev, uint next) = findPosition(
      offers,
      best.value,
      wants,
      gives,
      pivotId
    );

    /* Then we place the offer in the book at the position found by `findPosition`. */
    if (prev != 0) {
      offers[prev].next = uint32(offerId);
    } else {
      best.value = uint32(offerId);
    }

    if (next != 0) {
      offers[next].prev = uint32(offerId);
    }

    //TODO Check if Solidity optimizer prefers this or offers[i].a = a'; ... ; offers[i].b = b'
    /* With the `prev`/`next` in hand, we store the offer in the `offers` and `offerDetails` maps. Note that by `Dex`'s `newOffer` function, `offerId` will always fit in 32 bits. */
    offers[offerId] = Offer({
      prev: uint32(prev),
      next: uint32(next),
      wants: uint96(wants),
      gives: uint96(gives)
    });

    offerDetails[offerId] = OfferDetail({
      gasWanted: uint24(gasWanted),
      gasOverhead: uint24(config.gasOverhead),
      penaltyPerGas: uint48(config.penaltyPerGas),
      maker: msg.sender
    });

    /* And finally return the newly created offer id to the caller. */
    emit DexEvents.NewOffer(msg.sender, wants, gives, gasWanted, offerId);
    return offerId;
  }

  /* `findPosition` takes a price in the form of a `wants/gives` pair, an offer id (`pivotId`) and walks the book from that offer (backward or forward) until the right position for the price `wants/gives` is found. The position is returned as a `(prev,next)` pair, with `prev` or `next` at 0 to mark the beginning/end of the book (no offer ever has id 0).

  If prices are equal, `findPosition` will put the newest offer last. */
  function findPosition(
    mapping(uint => Offer) storage offers,
    /* As a backup pivot, the id of the current best offer is sent by `Dex` to `DexLib`. This is in case `pivotId` turns out to be an invalid offer id. This part of the code relies on consumed offers being deleted, otherwise we would blindly insert offers next to garbage old values. */
    uint bestValue,
    uint wants,
    uint gives,
    uint pivotId
  ) internal view returns (uint, uint) {
    Offer memory pivot = offers[pivotId];

    if (!isOffer(pivot)) {
      // in case pivotId is not or no longer a valid offer
      pivot = offers[bestValue];
      pivotId = bestValue;
    }

    // pivot price better than `wants/gives`, we follow next
    if (better(pivot.wants, pivot.gives, wants, gives)) {
      Offer memory pivotNext;
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
      Offer memory pivotPrev;
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
    require(freeWei[maker] >= amount, "insufficient provision");
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
