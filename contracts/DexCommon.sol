// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

/* # Dex Summary
   * Each Dex instance is half an offerbook for two ERC20 tokens.
   * Each offer promises `OFR_TOKEN` and requests `REQ_TOKEN`.
   * Each offer has an attached `maker` address.
   * When an offer is executed, we:
     1. Flashloan some `REQ_TOKEN` to the offer's `maker`.
     2. Call an arbitrary `execute` function on that address.
     3. Transfer back some `OFR_TOKEN`.
   * Offer are just promises. They can fail.
   * If an offer fails to transfer the right amount back, the loan is reverted.
   * A penalty mechanism incentivizes keepers to keep the book clean of failing offers.
   * A penalty provision must be posted with each offer.
   * If the offer succeeds, the provision returns to the maker.
   * If the offer fails, the provision is given to the taker as penalty.
   * The penalty should overcompensate for the taker's lost gas.
 */
//+clear+

library DexCommon {
  /* # Offer information */

  /* Offers are stored in a doubly-linked list, with all relevant offer data stored in structs `Offer` and `OfferDetail`. Functions often require only one of those structs to do their work. */
  //+clear+

  /* ## `Offer` */
  //+clear+
  /* `Offer`s hold the doubly-linked list pointers as well as price and volume information. 256 bits wide, so one storage read is enough. They have the following fields: */
  struct Offer {
    /* * `prev` points to the next best offer, and `next` points to the next worse. The best offer's `prev` is 0, and the last offer's `next` is 0 as well. _32 bits wide_. */
    uint32 prev;
    uint32 next;
    /* * `gives` is the amount of `OFR_TOKEN` the offer will give if successfully executed.
     _96 bits wide_, so assuming the usual 18 decimals, amounts can only go up to
  10 billions. */
    uint96 gives;
    /* * `wants` is the amount of `REQ_TOKEN` the offer wants in exchange for `gives`.
     _96 bits wide_, so assuming the usual 18 decimals, amounts can only go up to
  10 billions. */
    uint96 wants;
  }

  /* ## `OfferDetail`, provision info */
  //+clear+
  /* `OfferDetail`s hold the maker's address and provision/penalty-related information.
They have the following fields: */
  struct OfferDetail {
    /* * When an offer is executed, the function `execute` is called at
     the `maker` address, following this interface:

       ```
       interface IMaker {
         function execute(
           uint takerWants,
           uint takerGives,
           uint offerGasprice,
           uint offerId
         ) external;
       }
       ```

       Where `takerWants ≤ gives`, `takerGives/takerWants = wants/gives`,
       `offerGasprice` is how many `wei` a failed offer will pay per gas
       consumed, and `offerId` is the id of the offer being executed.

   */
    address maker;
    /* * `gasreq` gas will be provided to `execute`. _24 bits wide_, 33% more than the block limit as of late 2020. Note that if more room was needed, we could bring it down to 16 bits and have it represent 1k gas increments.

       Offer execution proceeds as follows:
       1. Send `wants` `REQ_TOKEN` from the taker to the maker,
       2. Call `IMaker(maker).execute{gas:gasreq}()`,
       3. Send `gives` `OFR_TOKEN` from the maker to the taker

       The function `execute` can be arbitrary code. The only requirement is that
       the transfer at step 3. succeeds. In that case, the offer _succeeds_.

       Otherwise the execution reverted and the maker is penalized.
       In that case, the offer _fails_.

  */
    uint24 gasreq;
    /*
     * `gasbase` represents the gas overhead used by processing the offer
       inside the Dex. The gas considered 'used' by an offer is at least
       `gasbase`, and at most `gasreq + gasbase`.

       If an offer fails, `gasprice` wei is taken from the
       provision per unit of gas used. `gasprice` should approximate the average gas
       price at offer creation time.

       So, when an offer is created, the maker is asked to provision the
       following amount of wei:
       ```
       (gasreq + gasbase) * gasprice
       ```
        When an offer fails, the following amount is given to the taker as compensation:
       ```
       (gasUsed + gasbase) * gasprice
       ```

       and the rest is given back to the maker.

       `gasprice` is _48 bits wide_, which accomodates ~280k gwei / gas. Note that if more room was needed, we could bring it down to 32 bits and have it represent mwei/gas (so up to 4M gwei/gas), or mwei/kgas (so up to 400k gwei/gas).
       `gasbase` is _24 bits wide_ -- note that if more room was needed, we could bring it down to 8 bits and have it represent 1k gas increments.

       Both `gasprice` and `gasbase` are also the names of global Dex
       parameters. When an offer is created, their current value is added to
       the offer's `OfferDetail`. The maker does not choose them.

    */
    uint24 gasbase;
    uint48 gasprice;
  }

  /* # Configuration
   All configuration information of the Dex is in a `Config` struct. Configuration fields are:
*/
  struct Config {
    bool dead;
    bool active;
    /* * `fee`, in basis points, of `OFR_TOKEN` given to the taker. This fee is sent to the Dex. Fee is capped to 5% (see Dex.sol). */
    uint fee;
    /* * The `gasprice` is the amount of penalty paid by failed offers, in wei per gas used. `gasprice` should approximate the average gas price and will be subject to regular updates. */
    uint gasprice;
    /* * `gasbase` is an overapproximation of the gas overhead associated with processing each offer. The Dex considers that a failed offer has used at leat `gasbase` gas. Should only be updated when opcode prices change. */
    uint gasbase;
    /* * `density` is similar to a 'dust' parameter. We prevent spamming of low-volume offers by asking for a minimum 'density' in `OFR_TOKEN` per gas requested. For instance, if `density == 10`, `gasbase == 5000` an offer with `gasreq == 30000` must promise at least _10 × (30000 + 5) = 305000_ `OFR_TOKEN`. */
    uint density;
    /*
    * An offer which asks for more gas than the block limit would live forever on
    the book. Nobody could take it or remove it, except its creator (who could cancel it). In practice, we will set this parameter to a reasonable limit taking into account both practical transaction sizes and the complexity of maker contracts.
  */
    uint gasmax;
  }

  /* # Misc.
   Finally, some miscellaneous things useful to both `Dex` and `DexLib`:*/
  //+clear+
  /* A container for `uint` that can be passed to an external library function as a storage reference so that the library can write the `uint` (in Solidity, references to storage value types cannot be passed around). This is used to send a writeable reference to the current best offer to the library functions of `DexLib` (`DexLib` exists to reduce the contract size of `Dex`). */
  struct UintContainer {
    uint value;
  }

  /* The Dex holds a `uint => Offer` mapping in storage. Offer ids that are not yet assigned or that point to since-deleted offer will point to an uninitialized struct. A common way to check for initialization is to add an `exists` field to the struct. In our case, an invariant of the Dex is: on an existing offer, `offer.gives > 0`. So we just check the `gives` field. */
  /* An important invariant is that an offer is 'live' iff (gives > 0) iff (the offer is in the book). */
  function isLive(Offer memory offer) internal pure returns (bool) {
    return offer.gives > 0;
  }

  /* Connect the predecessor and sucessor of `id` through their `next`/`prev` pointers. For more on the book structure, see `DexCommon.sol`. This step is not necessary during a market order, so we only call `dirtyDeleteOffer` */
  function stitchOffers(
    address base,
    address quote,
    mapping(address => mapping(address => mapping(uint => Offer)))
      storage offers,
    mapping(address => mapping(address => uint)) storage bests,
    uint past,
    uint future
  ) internal {
    if (past != 0) {
      offers[base][quote][past].next = uint32(future);
    } else {
      bests[base][quote] = future;
    }

    if (future != 0) {
      offers[base][quote][future].prev = uint32(past);
    }
  }

  /* Holds data about offers in a struct, used by `newOffer` to avoid stack too deep errors. */
  struct OfferPack {
    address base;
    address quote;
    uint wants;
    uint gives;
    uint id;
    uint gasreq;
    uint pivotId;
    Config config;
  }

  /* Holds data about orders in a struct, used by `marketOrder` and `internalSnipes` (and some of their nested functions) to avoid stack too deep errors. */
  struct OrderPack {
    address base;
    address quote;
    uint wants;
    uint gives;
    uint offerId;
    uint totalGot;
    uint totalGave;
    Offer offer;
    Config config;
    address governance;
    uint numFailures;
    uint[2][] failures;
  }

  enum SwapResult {OK, TakerTransferFail, MakerTransferFail, MakerReverted}
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
  event SetGasmax(uint value);
  event SetDensity(address base, address quote, uint value);
  event SetGasprice(uint value);

  /* * Offer execution */
  event Success(uint offerId, uint takerWants, uint takerGives);
  event MakerFail(
    uint offerId,
    uint takerWants,
    uint takerGives,
    bool reverted,
    uint makerData
  );

  /* * Dex closure */
  event Kill();

  /* * A new offer was inserted into book.
   `maker` is the address of the contract that implements the offer. */
  event NewOffer(
    address base,
    address quote,
    address maker,
    uint wants,
    uint gives,
    uint gasreq,
    uint offerId
  );
  /* * An offer was created/updated into book. Creation if offerId is new. */
  event UpdateOffer(uint wants, uint gives, uint gasreq, uint offerId);

  /* * An offer was canceled (and possibly erase). */
  event CancelOffer(uint offerId, bool erase);

  /* * `offerId` is was present and now removed from the book. */
  event DeleteOffer(uint offerId);
}
