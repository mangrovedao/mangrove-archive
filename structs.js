/* # Dex Summary
   * Each Dex instance is half an offerbook for two ERC20 tokens.
   * Each offer promises `base` and requests `quote`.
   * Each offer has an attached `maker` address.
   * When an offer is executed, we:
     1. Flashloan some `quote` to the offer's `maker`.
     2. Call an arbitrary `execute` function on that address.
     3. Transfer back some `base`.
   * Offer are just promises. They can fail.
   * If an offer fails to transfer the right amount back, the loan is reverted.
   * A penalty mechanism incentivizes keepers to keep the book clean of failing offers.
   * A penalty provision must be posted with each offer.
   * If the offer succeeds, the provision returns to the maker.
   * If the offer fails, the provision is given to the taker as penalty.
   * The penalty should overcompensate for the taker's lost gas.
 */
//+clear+

/* # Data stuctures */

/* Struct-like data structures are stored in storage and memory as 256 bits words. We avoid using structs due to significant gas savings gained by extracting data from words only when needed. To make development easier, we use the preprocessor `solpp` and generate getters and setters for each struct we declare. The generation is defined in `lib/preproc.js`. */

const preproc = require("./lib/preproc.js");

/* Struct fields that are common to multiple structs are factored here. Multiple field names refer to offer identifiers, so the `id` field is a function that takes a name as argument. */

const fields = {
  gives: { name: "gives", bits: 96, type: "uint" },
  wants: { name: "wants", bits: 96, type: "uint" },
  gasprice: { name: "gasprice", bits: 16, type: "uint" },
  gasreq: { name: "gasreq", bits: 24, type: "uint" },
  gasbase: { name: "gasbase", bits: 24, type: "uint" },
};

const id_field = (name) => {
  return { name, bits: 24, type: "uint" };
};

/* # Structs */

/* ## `Offer` */
//+clear+
/* `Offer`s hold the doubly-linked list pointers as well as price and volume information. 256 bits wide, so one storage read is enough. They have the following fields: */
/* Offers are stored in a doubly-linked list, with all relevant offer data stored in structs `Offer` and `OfferDetail`. Functions often require only one of those structs to do their work. */
//+clear+
const structs = {
  offer: [
    /* * `prev` points to the next best offer, and `next` points to the next worse. The best offer's `prev` is 0, and the last offer's `next` is 0 as well. _24 bits wide_. */
    id_field("prev"),
    id_field("next"),
    /* * `gives` is the amount of `base` the offer will give if successfully executed.
    _96 bits wide_, so assuming the usual 18 decimals, amounts can only go up to
    10 billions. */
    fields.gives,
    /* * `wants` is the amount of `quote` the offer wants in exchange for `gives`.
     _96 bits wide_, so assuming the usual 18 decimals, amounts can only go up to
  10 billions. */
    fields.wants,
    /* * `gasprice` is in gwei/gas and _16 bits wide_, which accomodates 1 to ~65k gwei / gas.  `gasprice` is also the name of global Dex parameters. When an offer is created, its current value is added to the offer's `Offer`. The maker may choose an upper bound. */
    fields.gasprice,
  ],

  /* ## `OfferDetail` */
  //+clear+
  /* `OfferDetail`s hold the maker's address and provision/penalty-related information.
They have the following fields: */
  offerDetail: [
    /* * `maker` is the address that created the offer. It will be called when the offer is executed, and later during the posthook phase. */
    { name: "maker", bits: 160, type: "address" },
    /* * `gasreq` gas will be provided to `execute`. _24 bits wide_, 33% more than the block limit as of late 2020. Note that if more room was needed, we could bring it down to 16 bits and have it represent 1k gas increments.

  */
    fields.gasreq,
    /*
     * `gasbase` represents the gas overhead used by processing the offer
       inside the Dex. The gas considered 'used' by an offer is at least
       `gasbase`, and at most `gasreq + gasbase`.

         If an offer fails, `gasprice` wei is taken from the
         provision per unit of gas used. `gasprice` should approximate the average gas
         price at offer creation time.

         `gasbase` is _24 bits wide_ -- note that if more room was needed, we could bring it down to 8 bits and have it represent 1k gas increments.

         `gasbase` is also the name of global Dex
         parameters. When an offer is created, its current value is added to
         the offer's `OfferDetail`. The maker does not choose it.

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

    */
    fields.gasbase,
  ],

  /* ## Configuration
   All configuration information of the Dex is in a `Config` struct. Configuration fields are:
*/
  /* ### Global Configuration. */
  global: [
    /* * The `monitor` can provide realtime values for `gasprice` and `density` to the dex, and receive liquidity events notifications. */
    { name: "monitor", bits: 160, type: "address" },
    /* * If `useOracle` is true, the dex will use the monitor address as an oracle for `gasprice` and `density`, for every base/quote pair. */
    { name: "useOracle", bits: 8, type: "uint" },
    /* * If `notify` is true, the dex will notify the monitor address after every offer execution. */
    { name: "notify", bits: 8, type: "uint" },
    /* * The `gasprice` is the amount of penalty paid by failed offers, in wei per gas used. `gasprice` should approximate the average gas price and will be subject to regular updates. */
    fields.gasprice,
    /* * `gasmax` specifies how much gas an offer may ask for at execution time. An offer which asks for more gas than the block limit would live forever on the book. Nobody could take it or remove it, except its creator (who could cancel it). In practice, we will set this parameter to a reasonable limit taking into account both practical transaction sizes and the complexity of maker contracts.
     */
    { name: "gasmax", bits: 24, type: "uint" },
    /* * `dead` dexes cannot be resurrected. */
    { name: "dead", bits: 8, type: "uint" },
  ],

  /* ### Local configuration */
  local: [
    /* * A `base`,`quote` pair is in`active` by default, but may be activated/deactivated by governance. */
    { name: "active", bits: 8, type: "uint" },
    /* * `fee`, in basis points, of `base` given to the taker. This fee is sent to the Dex. Fee is capped to 5% (see Dex.sol). */
    { name: "fee", bits: 16, type: "uint" },
    /* * `density` is similar to a 'dust' parameter. We prevent spamming of low-volume offers by asking for a minimum 'density' in `base` per gas requested. For instance, if `density == 10`, `gasbase == 5000` an offer with `gasreq == 30000` must promise at least _10 × (30000 + 5) = 305000_ `base`. */
    { name: "density", bits: 32, type: "uint" },
    /* * `gasbase` is an overapproximation of the gas overhead associated with processing each offer. The Dex considers that a failed offer has used at leat `gasbase` gas. Should only be updated when opcode prices change. */
    fields.gasbase,
    /* `best` a holds the current best offer id. Has size of an id field. ! danger ! reading best inside a lock may give you a stale value. */
    { name: "best", bits: 24, type: "uint" },
    /* * If `lock` is true, orders may not be added nor executed.

       Reentrancy during offer execution is not considered safe:
     * during execution, an offer could consume other offers further up in the book, effectively frontrunning the taker currently executing the offer.
     * it could also cancel other offers, creating a discrepancy between the advertised and actual market price at no cost to the maker.
     * an offer insertion consumes an unbounded amount of gas (because it has to be correctly placed in the book).

Note: An optimization in the `marketOrder` function relies on reentrancy being forbidden.
     */
    { name: "lock", bits: 8, type: "uint" },
    /* * `lastId` is a counter for offer ids, incremented every time a new offer is created. It can't go above 2^24-1. */
    { name: "lastId", bits: 24, type: "uint" },
  ],

  /* ## WriteOffer */
  /* `writeOffer` packs information about an offer that was just created/updated. It is used for logging compact data. */
  writeOffer: [
    fields.wants,
    fields.gives,
    fields.gasprice,
    fields.gasreq,
    id_field("id"),
  ],
};

/* # Example */
/* `preproc.structs_with_macros` generates preprocessor instruction to get/set all fields in the above structs. A preprocessor method `m(args)` is invoked in solidity code by writing `$$(m(args))`.

For instance, the structs object

```
{
  myStruct: [
    {name: "a", bits: 8,  type: "uint"},
    {name: "b", bits: 160, type: "address"}
  ]
}
```

will generate the following preprocessor macros:
* `set_myStruct(ptr,values)`. In a context where the solidity variable `v` holds an encoded `myStruct`, it can be used with `$$(set_myStruct('v',[['b','msg.sender']]))`. Note that solidity expression are given as strings. Here : `$$(set_myStruct('v',[['a',256]]))` and in all other methods, arguments exceeding the `bits` parameter of a field will be left-truncated.
* `make_myStruct(values)`. An optimised version of `set_myStruct` where the initial value is the null word.
* `myStruct_a(ptr)`, to access the `a` field. Returns a uint. If the solidity variable `v` holds an encoded `myStruct`, it can be used with `$$(myStruct_a('v'))`.
* `myStruct_b(ptr)`, to access the `b` field. Returns an address.

*/
module.exports = preproc.structs_with_macros(structs);
