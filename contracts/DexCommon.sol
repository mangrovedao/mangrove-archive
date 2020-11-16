// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.1;

/* # Dex Summary
   * Each contract is half an offerbook for two ERC20 tokens.
   * Each maker's offer promises `OFR_TOKEN` and requests `REQ_TOKEN`.
   * Executing an offer means:
     1. Flashloaning some `REQ_TOKEN` to a contract.
     2. Calling arbitrary code on that contract.
   * Offer are just promises. They can fail.
   * A safety provision must be posted with each offer.
   * If the offer succeeds, the provision returns to the maker.
   * If the offer fails, the provision is given to the taker as penalty.
   * The penalty should compensate for the taker's lost gas.
   * This incentivizes keepers to keep the book clean of failing offers.
 */
//+clear+

/* # Offer information */

/* Offers are stored in a doubly-linked list, with all relevant offer data stored in structs `Offer` and `OfferDetail`. Functions often require only one of those structs to do their work. */
//+clear+

/* ## `Offer` */
//+clear+
/* `Offer`s hold the doubly-linked list pointers as well as price and volume information. 256 bits wide, so one storage read is enough. They have the following fields: */
struct Offer {
  /* * `prev` points to the next best offer, and `next` points to the next worse. The best offer's `prev` is 0, and the last offer's last is 0 as well. _32 bits_. */
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
  /* * `gasreq` gas will be provided to `execute`. _24 bits wide_, 33% more than the block limit as of late 2020.

       Around execution, the Dex will:
       1. Send `wants` `REQ_TOKEN` from `msg.sender` to `maker`,
       2. Call `IMaker(maker).execute{gas:gasreq}()`,
       3. Send `gives` `OFR_TOKEN` from `maker` to `msg.sender`.

       The function `execute` can be arbitrary code. The only requirement is that
       the transfer at step 3. succeeds. In that case, the offer _succeeds_.

       Otherwise the execution reverted and the maker is penalized.
       In that case, the offer _fails_.

  */
  uint24 gasreq;
  /*
     * If an offer fails, `gasprice` is the amount (in wei) taken from the
       provision per unit of gas used. It should approximate the average gas
       price at offer creation time.

       `gasbase` represents the gas overhead used by processing the offer
       inside the Dex. The gas considered used by an offer is at least
       `gasbase`, and at most `gasreq + gasbase`.


       So, when an offer is created, the maker is asked to provision the
       following amount of wei:
       ```
       (gasreq + gasbase) * gasprice
       ```
        When an offer fails, the following amount is given to the taker as compensation:
       ```
       (gasUsed + gasbase) * gasprice
       ```

       and the rest is added back to the maker's 'available provision' balance
       (a global map called `freeWei`).

       `gasprice` is **48 bits wide**, which accomodates ~280k gwei / gas.
       `gasbase` is **24 bits wide**, it could be 16 bits wide but we are
       leaving a margin of safety for future gas repricings.

       Both `gasprice` and `gasbase` are also the names of global Dex
       parameters. When an offer is created, their current value is added to
       the offer's `OfferDetail`. The maker does not choose them.

    */
  uint48 gasprice;
  uint24 gasbase;
}

/* # Configuration
   All configuration information of the Dex is in a `Config` struct. An enum `ConfigKey` matches the struct fields. Updates and reads go through the Dex'es `getConfig*` (one version per type) and `setConfigKey` (overloaded per type) function. They take a `ConfigKey` as first argument. Configuration fields are:
*/
struct Config {
  /* * The `admin`, allowed to change anything in the configuration and irreversibly
     close the market. It has no other powers. */
  address admin;
  /* * `fee`, in basis points, of `OFR_TOKEN` given to the taker. This fee is sent to the Dex. */
  uint fee;
  /* * The `gasprice` is the amount of penalty paid by failed offers, in wei per gas used. `gasprice` should approximate the average gas price and will be subject to regular updates. */
  uint gasprice;
  /* * `gasbase` is an overapproximation of the gas overhead associated with processing each offer. The Dex considers that a failed offer has used at leat `gasbase` gas. Should only be updated when opcode prices change. */
  uint gasbase;
  /* * `density` is a 'dust' parameter in `OFR_TOKEN` per gas. A weakness of offerbook-based exchanges is that a market offer is not gas-constant. We prevent spamming of low-volume offers by asking for a minimum 'density'. For instance, if `density == 10`, `gasbase == 5` an offer with `gasreq == 30000` must offer promise at least [_10 × (30000 + 5) = 300050_](provision-formula) `OFR_TOKEN`. */
  uint density;
  /*
    * An offer which asks for more gas than the block limit would live forever on
    the book. Nobody could take it or remove it, except its creator (who could cancel it). In practice, we will set this parameter to a reasonable limit taking into account both practical transaction sizes and the complexity of maker contracts.
  */
  uint gasmax;
}

/* Every configuration parameter in the `Config` struct has a counterpart in the `ConfigKey` enum. To get and set the configuration, generic functions (one per type) in `DexLib`
   accept a `ConfigKey` as first argument, and the setter functions takes a value
   as second argument. */
enum ConfigKey {admin, fee, gasprice, gasbase, density, gasmax}

/* # Events
The events emitted for use by various bots are listed here: */
library DexEvents {
  event TestEvent(uint);

  /* * Dex sends amount to receiver */
  event Transfer(address payable receiver, uint amout);

  /* * Dex adds or removes wei from `maker`'s account */
  event Credit(address maker, uint amount);
  event Debit(address maker, uint amount);

  /* * Dex reconfiguration */
  event SetFee(uint value);
  event SetGasmax(uint value);
  event SetDustPerGasWanted(uint value);
  event SetGasprice(uint value);
  event SetAdmin(address addr);

  /* * Offer execution */
  event Success(uint offerId, uint takerWants, uint takerGives);
  event Failure(uint offerId, uint takerWants, uint takerGives);

  /* * Dex closure */
  event CloseMarket();

  /* * `offerId` was successfully cancelled.
     No event is emitted if `offerId` is absent from book. */
  event CancelOffer(uint offerId);

  /* * A new offer was inserted into book.
   `maker` is the address of the contract that implements the offer. */
  event NewOffer(
    address maker,
    uint wants,
    uint gives,
    uint gasreq,
    uint offerId
  );

  /* * `offerId` is removed from book. */
  event DeleteOffer(uint offerId);
}

/* # Misc.
   Finally, some miscallaneous things useful to both `Dex` and `DexLib`:*/
//+clear+
/* Part of the Dex state is the current best offer on the book (a `uint`). That state must be writable by functions of `DexLib` (`DexLib` exists to reduce the contract size of `Dex`). Since storage pointers to value types cannot be passed around, we wrap the  */
struct UintContainer {
  uint value;
}

/* At several points, the Dex must retrieve an offer based on an `offerId`. Ids that are not yet assigned or that point to since-deleted offer will point to a uninitialized struct. The simplest way to check that is to check that a dedicated field is 0. Since an invariant of the Dex is that an active offer will never `gives` less than 1 `OFR_TOKEN`, we check the `gives` field. */
function isOffer(Offer memory offer) pure returns (bool) {
  return offer.gives > 0;
}
