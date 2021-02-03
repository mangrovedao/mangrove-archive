// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

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
    /* The monitor, can provide realtime values for `gasprice` and `density` to the dex, and receive liquidity events notifications. */
    address monitor;
    /* If true, the dex will use the monitor address as an oracle for `gasprice` and `density`, for every base/quote pair. */
    bool useOracle;
    /* If true, the dex will notify the monitor address after every offer execution. */
    bool notify;
    /* * The `gasprice` is the amount of penalty paid by failed offers, in wei per gas used. `gasprice` should approximate the average gas price and will be subject to regular updates. */
    uint gasprice;
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
    /* * `gasbase` is an overapproximation of the gas overhead associated with processing each offer. The Dex considers that a failed offer has used at leat `gasbase` gas. Should only be updated when opcode prices change. */
    uint gasbase;
    /* * If `lock` is true, orders may not be added nor executed.

       Reentrancy during offer execution is not considered safe:
     * during execution, an offer could consume other offers further up in the book, effectively frontrunning the taker currently executing the offer.
     * it could also cancel other offers, creating a discrepancy between the advertised and actual market price at no cost to the maker.
     * an offer insertion consumes an unbounded amount of gas (because it has to be correctly placed in the book).

Note: An optimization in the `marketOrder` function relies on reentrancy being forbidden.
     */
    bool lock;
    /* `best` a holds the current best offer id. Has size of an id field. ! danger ! reading best inside a lock may give you a stale value. */
    uint best;
    /* * `lastId` is a counter for offer ids, incremented every time a new offer is created. It can't go above 2^24-1. */
    uint lastId;
  }

  struct Config {
    Global global;
    Local local;
  }

  /* # Misc.
   Finally, some miscellaneous things useful to both `Dex` and `DexLib`:*/
  //+clear+
  /* A container for `uint` that can be passed to an external library function as a storage reference so that the library can write the `uint` (in Solidity, references to storage value types cannot be passed around). This is used to send a writeable reference to the current best offer to the library functions of `DexLib` (`DexLib` exists to reduce the contract size of `Dex`). */

  /* Holds data about orders in a struct, used by `marketOrder` and `internalSnipes` (and some of their nested functions) to avoid stack too deep errors. */
  struct SingleOrder {
    address base;
    address quote;
    uint offerId;
    bytes32 offer;
    /* will evolve over time, initially the wants/gives from the taker's pov,
       then actual wants/give depending on how much the offer is ready */
    uint wants;
    uint gives;
    /* only populated when necessary */
    bytes32 offerDetail;
  }

  struct OrderResult {
    address taker;
    bool success;
    bytes32 makerData;
  }
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
  event SetGovernance(address value);
  event SetMonitor(address value);
  event SetVault(address value);
  event SetUseOracle(bool value);
  event SetNotify(bool value);
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

  /* * `offerId` was present and is now removed from the book. */
  event RetractOffer(address base, address quote, uint offerId);

  /* *Dead offer `offerId` is collected: provision is withdrawn and `offerId` is removed from `offers` and `offerDetails` maps*/
  event DeleteOffer(address base, address quote, uint offerId);
}

interface IMaker {
  // Maker sends quote to taker
  // In normal dex, they already received base
  // In inverted dex, they did not
  //function makerTrade(Trade calldata trade) external returns (bytes32);

  // Maker sends quote to taker
  // In normal dex, they already received base
  // In inverted dex, they did not
  function makerTrade(DexCommon.SingleOrder calldata order)
    external
    returns (bytes32);

  // Maker callback after trade
  function makerPosthook(
    DexCommon.SingleOrder calldata order,
    DexCommon.OrderResult calldata result
  ) external;

  event Execute(
    address dex,
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  );
}

interface ITaker {
  // Inverted dex only: taker acquires enough base to pay back quote loan
  function takerTrade(
    address base,
    address quote,
    uint totalGot,
    uint totalGives
  ) external;
}

/* Monitor contract interface */
interface IDexMonitor {
  function notifySuccess(DexCommon.SingleOrder calldata sor, address taker)
    external;

  function notifyFail(DexCommon.SingleOrder calldata sor) external;

  function read(address base, address quote)
    external
    returns (uint gasprice, uint density);
}
