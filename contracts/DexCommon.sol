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
    /* * `prev` points to the next best offer, and `next` points to the next worse. The best offer's `prev` is 0, and the last offer's `next` is 0 as well. _24 bits wide_. */
    uint prev;
    uint next;
    /* * `gives` is the amount of `OFR_TOKEN` the offer will give if successfully executed.
     _96 bits wide_, so assuming the usual 18 decimals, amounts can only go up to
  10 billions. */
    uint gives;
    /* * `wants` is the amount of `REQ_TOKEN` the offer wants in exchange for `gives`.
     _96 bits wide_, so assuming the usual 18 decimals, amounts can only go up to
  10 billions. */
    uint wants;
    /* `gasprice` is in gwei/gas and _16 bits wide_, which accomodates 1 to ~65k gwei / gas.

          `gasprice` is also the name of global Dex
          parameters. When an offer is created, its current value is added to
          the offer's `Offer`. The maker may choose an upper bound. */
    uint gasprice;
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
    uint gasreq;
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
       (gasused + gasbase) * gasprice
       ```

       and the rest is given back to the maker.

       `gasbase` is _24 bits wide_ -- note that if more room was needed, we could bring it down to 8 bits and have it represent 1k gas increments.

       `gasbase` is also the name of global Dex
       parameters. When an offer is created, its current value is added to
       the offer's `OfferDetail`. The maker does not choose it.

    */
    uint gasbase;
  }

  /* # Configuration
   All configuration information of the Dex is in a `Config` struct. Configuration fields are:
*/
  /* Configuration. See DexLib for more information. */
  struct Global {
    /* * The `gasprice` is the amount of penalty paid by failed offers, in wei per gas used. `gasprice` should approximate the average gas price and will be subject to regular updates. */
    uint gasprice;
    /* * `gasbase` is an overapproximation of the gas overhead associated with processing each offer. The Dex considers that a failed offer has used at leat `gasbase` gas. Should only be updated when opcode prices change. */
    uint gasbase;
    /* An offer which asks for more gas than the block limit would live forever on
    the book. Nobody could take it or remove it, except its creator (who could cancel it). In practice, we will set this parameter to a reasonable limit taking into account both practical transaction sizes and the complexity of maker contracts.
  */
    uint gasmax;
    bool dead;
  }

  struct Local {
    bool active;
    /* * `fee`, in basis points, of `OFR_TOKEN` given to the taker. This fee is sent to the Dex. Fee is capped to 5% (see Dex.sol). */
    uint fee;
    /* * `density` is similar to a 'dust' parameter. We prevent spamming of low-volume offers by asking for a minimum 'density' in `OFR_TOKEN` per gas requested. For instance, if `density == 10`, `gasbase == 5000` an offer with `gasreq == 30000` must promise at least _10 × (30000 + 5) = 305000_ `OFR_TOKEN`. */
    uint density;
  }

  struct Config {
    Global global;
    Local local;
  }

  /* # Misc.
   Finally, some miscellaneous things useful to both `Dex` and `DexLib`:*/
  //+clear+
  /* A container for `uint` that can be passed to an external library function as a storage reference so that the library can write the `uint` (in Solidity, references to storage value types cannot be passed around). This is used to send a writeable reference to the current best offer to the library functions of `DexLib` (`DexLib` exists to reduce the contract size of `Dex`). */
  struct UintContainer {
    uint value;
  }

  /* Holds data about offers in a struct, used by `newOffer` to avoid stack too deep errors. */
  struct OfferPack {
    address base;
    address quote;
    uint wants;
    uint gives;
    uint id;
    uint gasreq;
    uint gasprice;
    uint pivotId;
    bytes32 global;
    bytes32 local;
    bytes32 oldOffer;
  }

  /* Holds data about orders in a struct, used by `marketOrder` and `internalSnipes` (and some of their nested functions) to avoid stack too deep errors. */
  struct OrderPack {
    address base;
    address quote;
    uint initialWants;
    uint initialGives;
    uint offerId;
    uint totalGot;
    uint totalGave;
    bytes32 offer;
    bytes32 global;
    bytes32 local;
    uint numToPunish;
    uint[2][] toPunish;
    /* will evolve over time, initially the wants/gives from the taker's pov,
       then actual wants/give depending on how much the offer is ready */
    uint wants;
    uint gives;
    /* only populated when necessary */
    bytes32 offerDetail;
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
  event Success(
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  );
  event MakerFail(
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives,
    bool reverted,
    bytes32 makerData
  );

  /* * Dex closure */
  event Kill();

  /* * A new offer was inserted into book.
   `maker` is the address of the contract that implements the offer. */
  event WriteOffer(address base, address quote, address maker, bytes32 data);

  /* * An offer was canceled (and possibly erase). */
  event CancelOffer(address base, address quote, uint offerId, bool erase);

  /* * `offerId` is was present and now removed from the book. */
  event DeleteOffer(address base, address quote, uint offerId);
}
