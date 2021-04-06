// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;
import {
  ITaker,
  IMaker,
  DexCommon as DC,
  DexEvents,
  IDexMonitor
} from "./DexCommon.sol";
import "./interfaces.sol";

/*
   This contract describes an orderbook-based exchange ("Dex") where market makers *do not have to provision their offer*. See `structs.js` for a longer introduction. In a nutshell: each offer created by a maker specifies an address (`maker`) to call upon offer execution by a taker. In the normal mode of operation ('Flash Maker'), the Dex transfers the amount to be paid by the taker to the maker, calls the maker, attempts to transfer the amount promised by the maker to the taker, and reverts if it cannot.

   There is one Dex contract that manages all tradeable pairs. This reduces deployment costs for new pairs and makes it easier to have maker provisions for all pairs in the same place.

   There is a secondary mode of operation ('Flash Taker') in which the _maker_ flashloans the sold amount to the taker.

   The Dex contract is `abstract` and accomodates both modes. Two contracts, `FMD` (Flash Maker Dex) and `FTD` (Flash Taker Dex) inherit from it, one per mode of operation.
 */
abstract contract Dex {
  /* # State variables */
  //+clear+
  /* The `governance` address. Governance is the only address that can configure parameters. */
  address public governance;

  /* The `vault` address. If a pair has fees >0, those fees are sent to the vault. */
  address public vault;

  /* Global dex configuration, encoded in a 256 bits word. The information encoded is detailed in `structs.js`. */
  bytes32 public global;
  /* Configuration mapping for each token pair. The information is also detailed in `structs.js`. */
  mapping(address => mapping(address => bytes32)) public locals;

  /* The signature of the low-level swapping function. Given at construction time by inheriting contracts. In FMD, for each offer executed, `FLASHLOANER` sends from taker to maker, then calls maker. In FTD, `FLASHLOANER` first sends from maker to taker for each offer, then calls taker once, then transfers back to each maker. */
  bytes4 immutable FLASHLOANER;

  /* Given a `base`,`quote` pair, the mappings `offers` and `offerDetails` associate two 256 bits words to each offer id. Those words encode information detailed in `structs.js`.

     The mapping are `base => quote => offerId => bytes32`.
   */
  mapping(address => mapping(address => mapping(uint => bytes32)))
    public offers;
  mapping(address => mapping(address => mapping(uint => bytes32)))
    public offerDetails;

  /* Takers may provide allowances on specific pairs, so other addresses can execute orders in their name. Allowance may be set using the usual `approve` function, or through an [EIP712](https://eips.ethereum.org/EIPS/eip-712) `permit`.

  The mapping is `base => quote => owner => spender => allowance` */
  mapping(address => mapping(address => mapping(address => mapping(address => uint))))
    public allowances;
  /* Storing nonces avoids replay attacks. */
  mapping(address => uint) public nonces;
  /* Following [EIP712](https://eips.ethereum.org/EIPS/eip-712), structured data signing has `keccak256("Permit(address base,address quote,address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")` in its prefix. */
  bytes32 public constant PERMIT_TYPEHASH =
    0xb7bf278e51ab1478b10530c0300f911d9ed3562fc93ab5e6593368fe23c077a2;
  /* Initialized in the constructor, `DOMAIN_SEPARATOR` avoids cross-application permit reuse. */
  bytes32 public immutable DOMAIN_SEPARATOR;

  /* Makers provision their possible penalties in the `balanceOf` mapping.

       Offers specify the amount of gas they require for successful execution (`gasreq`). To minimize book spamming, market makers must provision a *penalty*, which depends on their `gasreq` and on the pair's `*_gasbase`. This provision is deducted from their `balanceOf`. If an offer fails, part of that provision is given to the taker, as retribution. The exact amount depends on the gas used by the offer before failing.

       The Dex keeps track of their available balance in the `balanceOf` map, which is decremented every time a maker creates a new offer, and may be modified on offer updates/cancelations/takings.
   */
  mapping(address => uint) public balanceOf;

  /*
  # Dex Constructor
  To initialize a new instance, the deployer must provide initial configuration (see `structs.js` for more on configuration parameters):
  */
  constructor(
    /* `_gasprice` is underscored to avoid builtin `gasprice` name shadowing. */
    uint _gasprice,
    uint gasmax,
    /* `takerLends` determines whether the taker or maker does the flashlend. FMD initializes with `true`, FTD initializes with `false`. */
    bool takerLends,
    /* Used by [EIP712](https://eips.ethereum.org/EIPS/eip-712)'s `DOMAIN_SEPARATOR` */
    string memory contractName //+clear+
  ) {
    emit DexEvents.NewDex();

    /* Initialize governance. At this stage we cannot use the `setGovernance` method since no admin is set. */
    governance = msg.sender;
    emit DexEvents.SetGovernance(msg.sender);

    /* Initialize vault to sender's address, and set initial gasprice and gasmax. */
    setVault(msg.sender);
    setGasprice(_gasprice);
    setGasmax(gasmax);
    /* In FMD, takers lend the liquidity to the maker. */
    /* In FTD, takers come ask the makers for liquidity. */
    FLASHLOANER = takerLends
      ? Dex.flashloan.selector
      : Dex.invertedFlashloan.selector;

    /* Initialize [EIP712](https://eips.ethereum.org/EIPS/eip-712) `DOMAIN_SEPARATOR`. */
    uint chainId;
    assembly {
      chainId := chainid()
    }
    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        keccak256(
          "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        ),
        keccak256(bytes(contractName)),
        keccak256(bytes("1")),
        chainId,
        address(this)
      )
    );
  }

  /* # Configuration */
  /* Returns the configuration in an ABI-compatible struct. Should not be called internally, would be a huge memory copying waste. Use `config` instead. */
  function getConfig(address base, address quote)
    external
    returns (DC.Config memory ret)
  {
    (bytes32 _global, bytes32 _local) = config(base, quote);
    ret.global = DC.Global({
      monitor: $$(global_monitor("_global")),
      useOracle: $$(global_useOracle("_global")) > 0,
      notify: $$(global_notify("_global")) > 0,
      gasprice: $$(global_gasprice("_global")),
      gasmax: $$(global_gasmax("_global")),
      dead: $$(global_dead("_global")) > 0
    });
    ret.local = DC.Local({
      active: $$(local_active("_local")) > 0,
      overhead_gasbase: $$(local_overhead_gasbase("_local")),
      offer_gasbase: $$(local_offer_gasbase("_local")),
      fee: $$(local_fee("_local")),
      density: $$(local_density("_local")),
      best: $$(local_best("_local")),
      lock: $$(local_lock("_local")) > 0,
      last: $$(local_last("_local"))
    });
  }

  /* Returns information about an offer in ABI-compatible structs. Do not use internally, would be a huge memory-copying waste. Use `offers[base][quote]` and `offerDetails[base][quote]` instead. */
  function offerInfo(
    address base,
    address quote,
    uint offerId
  ) external view returns (DC.Offer memory, DC.OfferDetail memory) {
    bytes32 offer = offers[base][quote][offerId];
    DC.Offer memory offerStruct =
      DC.Offer({
        prev: $$(offer_prev("offer")),
        next: $$(offer_next("offer")),
        wants: $$(offer_wants("offer")),
        gives: $$(offer_gives("offer")),
        gasprice: $$(offer_gasprice("offer"))
      });

    bytes32 offerDetail = offerDetails[base][quote][offerId];

    DC.OfferDetail memory offerDetailStruct =
      DC.OfferDetail({
        maker: $$(offerDetail_maker("offerDetail")),
        gasreq: $$(offerDetail_gasreq("offerDetail")),
        overhead_gasbase: $$(offerDetail_overhead_gasbase("offerDetail")),
        offer_gasbase: $$(offerDetail_offer_gasbase("offerDetail"))
      });
    return (offerStruct, offerDetailStruct);
  }

  /* Convenience function to get best offer of the given pair */
  function best(address base, address quote) external view returns (uint) {
    bytes32 local = locals[base][quote];
    return $$(local_best("local"));
  }

  /* Convenience function to check whether given pair is locked */
  function locked(address base, address quote) external view returns (bool) {
    bytes32 local = locals[base][quote];
    return $$(local_lock("local")) > 0;
  }

  /* Check whether an offer is 'live', that is: inserted in the order book. The Dex holds a `base => quote => id => bytes32` mapping in storage. Offer ids that are not yet assigned or that point to since-deleted offer will point to the null word. A common way to check for initialization is to add an `exists` field to a struct. In our case, liveness can be denoted by `offer.gives > 0`. So we just check the `gives` field. */
  function isLive(bytes32 offer) public pure returns (bool) {
    return $$(offer_gives("offer")) > 0;
  }

  /*
  # Gatekeeping

  Gatekeeping functions are safety checks called in various places.
  */

  /* `unlockedMarketOnly` protects modifying the market while an order is in progress. Since external contracts are called during orders, allowing reentrancy would, for instance, let a market maker replace offers currently on the book with worse ones. Note that the external contracts _will_ be called again after the order is complete, this time without any lock on the market.  */
  function unlockedMarketOnly(bytes32 local) internal pure {
    require($$(local_lock("local")) == 0, "dex/reentrancyLocked");
  }

  /* <a id="Dex/definition/liveDexOnly"></a>
     In case of emergency, the Dex can be `kill`ed. It cannot be resurrected. When a Dex is dead, the following operations are disabled :
       * Executing an offer
       * Sending ETH to the Dex the normal way. Usual [shenanigans](https://medium.com/@alexsherbuck/two-ways-to-force-ether-into-a-contract-1543c1311c56) are possible.
       * Creating a new offer
   */
  function liveDexOnly(bytes32 _global) internal pure {
    require($$(global_dead("_global")) == 0, "dex/dead");
  }

  /* When the Dex is deployed, all pairs are inactive by default (since `locals[base][quote]` is 0 by default). Offers on inactive pairs cannot be taken or created. They can be updated and retracted. */
  function activeMarketOnly(bytes32 _global, bytes32 _local) internal pure {
    liveDexOnly(_global);
    require($$(local_active("_local")) > 0, "dex/inactive");
  }

  /* # Public Maker operations
     ## New Offer */
  //+clear+
  /* In the Dex, makers and takers call separate functions. Market makers call `newOffer` to fill the book, and takers call functions such as `marketOrder` to consume it.  */

  //+clear+

  /* The following structs holds offer creation/update parameters in memory. This frees up stack space for local variables. */
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
    // used on update only
    bytes32 oldOffer;
  }

  /* The function `newOffer` is for market makers only; no match with the existing book is done. A maker specifies how much `quote` it `wants` and how much `base` it `gives`.

     It also specify with `gasreq` how much gas should be given when executing their offer.

     `gasprice` indicates an upper bound on the gasprice at which the maker is ready to be penalised if their offer fails. Any value below the Dex's internal `gasprice` configuration value will be ignored.

    `gasreq`, together with `gasprice`, will contribute to determining the penalty provision set aside by the Dex from the market maker's `balanceOf` balance.

  Offers are always inserted at the correct place in the book. This requires walking through offers to find the correct insertion point. As in [Oasis](https://github.com/daifoundation/maker-otc/blob/f2060c5fe12fe3da71ac98e8f6acc06bca3698f5/src/matching_market.sol#L493), the maker should find the id of an offer close to its own and provide it as `pivotId`.

  An offer cannot be inserted in a closed market, nor when a reentrancy lock for `base`,`quote` is on.

  No more than $2^{24}-1$ offers can ever be created for one `base`,`quote` pair.

  The actual contents of the function is in `writeOffer`, which is called by both `newOffer` and `updateOffer`.
  */
  function newOffer(
    address base,
    address quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) external returns (uint) {
    /* In preparation for calling `writeOffer`, we read the `base`,`quote` pair configuration, check for reentrancy and market liveness, fill the `OfferPack` struct and increment the `base`,`quote` pair's `last`. */
    OfferPack memory ofp;
    (ofp.global, ofp.local) = config(base, quote);
    unlockedMarketOnly(ofp.local);
    activeMarketOnly(ofp.global, ofp.local);

    ofp.id = 1 + $$(local_last("ofp.local"));
    require(uint24(ofp.id) == ofp.id, "dex/offerIdOverflow");

    ofp.local = $$(set_local("ofp.local", [["last", "ofp.id"]]));

    ofp.base = base;
    ofp.quote = quote;
    ofp.wants = wants;
    ofp.gives = gives;
    ofp.gasreq = gasreq;
    ofp.gasprice = gasprice;
    ofp.pivotId = pivotId;

    /* The second parameter to writeOffer indicates that we are creating a new offer, not updating an existing one. */
    writeOffer(ofp, false);

    /* Since we locally modified a field of the local configuration (`last`), we save the change to storage. Note that `writeOffer` may have further modified the local configuration by updating the current `best` offer. */
    locals[ofp.base][ofp.quote] = ofp.local;
    return ofp.id;
  }

  /* ## Update Offer */
  //+clear+
  /* Very similar to `newOffer`, `updateOffer` prepares an `OfferPack` for `writeOffer`. Makers should use it for updating live offers, but also to save on gas by reusing old, already consumed offers.

     A `pivotId` should still be given to minimise reads in the offer book. It is OK to give the offers' own id as a pivot.


     Gas use is minimal when:
     1. The offer does not move in the book
     2. The offer does not change its `gasreq`
     3. The (`base`,`quote`)'s `*_gasbase` has not changed since the offer was last written
     4. `gasprice` has not changed since the offer was last written
     5. `gasprice` is greater than the Dex's gasprice estimation
  */
  function updateOffer(
    address base,
    address quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) external returns (uint) {
    OfferPack memory ofp;
    (ofp.global, ofp.local) = config(base, quote);
    unlockedMarketOnly(ofp.local);
    activeMarketOnly(ofp.global, ofp.local);
    ofp.base = base;
    ofp.quote = quote;
    ofp.wants = wants;
    ofp.gives = gives;
    ofp.id = offerId;
    ofp.gasreq = gasreq;
    ofp.gasprice = gasprice;
    ofp.pivotId = pivotId;
    ofp.oldOffer = offers[base][quote][offerId];
    // Save local config
    bytes32 oldLocal = ofp.local;
    /* The second argument indicates that we are updating an existing offer, not creating a new one. */
    writeOffer(ofp, true);
    /* We saved the current pair's configuration before calling `writeOffer`, since that function may update the current `best` offer. We now check for any change to the configuration and update it if needed. */
    if (oldLocal != ofp.local) {
      locals[ofp.base][ofp.quote] = ofp.local;
    }
    return ofp.id;
  }

  /* ## Retract Offer */
  //+clear+
  /* `retractOffer` takes the offer `offerId` out of the book. However, `_deprovision == true` also refunds the provision associated with the offer. */
  function retractOffer(
    address base,
    address quote,
    uint offerId,
    bool _deprovision
  ) external {
    (, bytes32 local) = config(base, quote);
    unlockedMarketOnly(local);
    bytes32 offer = offers[base][quote][offerId];
    bytes32 offerDetail = offerDetails[base][quote][offerId];
    require(
      msg.sender == $$(offerDetail_maker("offerDetail")),
      "dex/retractOffer/unauthorized"
    );

    /* Here, we are about to un-live an offer, so we start by taking it out of the book by stitching together its previous and next offers. Note that unconditionally calling `stitchOffers` would break the book since it would connect offers that may have since moved. */
    if (isLive(offer)) {
      bytes32 oldLocal = local;
      local = stitchOffers(
        base,
        quote,
        $$(offer_prev("offer")),
        $$(offer_next("offer")),
        local
      );
      /* If calling `stitchOffers` has changed the current `best` offer, we update the storage. */
      if (oldLocal != local) {
        locals[base][quote] = local;
      }
      /* Set `gives` to 0. Moreover, the last argument depends on whether the user wishes to get their provision back. */
      dirtyDeleteOffer(base, quote, offerId, offer, _deprovision);
    }

    /* If the user wants to get their provision back, we compute its provision from the offer's `gasprice`, `*_gasbase` and `gasreq`. */
    if (_deprovision) {
      uint provision =
        10**9 *
          $$(offer_gasprice("offer")) * //gasprice is 0 if offer was deprovisioned
          ($$(offerDetail_gasreq("offerDetail")) +
            $$(offerDetail_overhead_gasbase("offerDetail")) +
            $$(offerDetail_offer_gasbase("offerDetail")));
      // credit `balanceOf` and log transfer
      creditWei(msg.sender, provision);
    }
    emit DexEvents.RetractOffer(base, quote, offerId);
  }

  /* ## Provisioning
  Market makers must have enough provisions for possible penalties. These provisions are in ETH. Every time a new offer is created or an offer is updated, `balanceOf` is adjusted to provision the offer's maximum possible penalty (`gasprice * (gasreq + overhead_gasbase + offer_gasbase)`). 

  For instance, if the current `balanceOf` of a maker is 1 ether and they create an offer that requires a provision of 0.01 ethers, their `balanceOf` will be reduced to 0.99 ethers. No ethers will move; this is just an internal accounting movement to make sure the maker cannot `withdraw` the provisioned amounts.

  */
  //+clear+

  /* Fund may be called with a nonzero value (hence the `payable` modifier). The provision will be given to `maker`, not `msg.sender`. */
  function fund(address maker) public payable {
    (bytes32 _global, ) = config(address(0), address(0));
    liveDexOnly(_global);
    creditWei(maker, msg.value);
  }

  /* A transfer with enough gas to the Dex will increase the caller's available `balanceOf` balance. _You should send enough gas to execute this function when sending money to the Dex._  */
  receive() external payable {
    fund(msg.sender);
  }

  /* Any provision not currently held to secure an offer's possible penalty is available for withdrawal. */
  function withdraw(uint amount) external returns (bool noRevert) {
    /* Since we only ever send money to the caller, we do not need to provide any particular amount of gas, the caller should manage this herself. */
    debitWei(msg.sender, amount);
    (noRevert, ) = msg.sender.call{value: amount}("");
  }

  /* # Public Taker operations */
  //+clear+

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

  /* The delegate version of `marketOrder` is `marketOrderFor`, which takes a `taker` address as additional argument. Penalties incurred by failed offers will still be sent to `msg.sender`, but exchanged amounts will be transferred from and to the `taker`. If the `msg.sender`'s allowance for the given `base`,`quote` and `taker` are strictly less than the total amount eventually spent by `taker`, the call will fail. */
  function marketOrderFor(
    address base,
    address quote,
    uint takerWants,
    uint takerGives,
    address taker
  ) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave) = generalMarketOrder(
      base,
      quote,
      takerWants,
      takerGives,
      taker
    );
    deductSenderAllowance(base, quote, taker, takerGave);
  }

  /* ## Sniping */
  //+clear+
  /* `snipe` takes a single offer `offerId` from the book. Since offers can be updated, we specify `takerWants`,`takerGives` and `gasreq`, and only execute if the offer price is acceptable and the offer's gasreq does not exceed `gasreq`.

  It is possible to ask for 0, so we return an additional boolean indicating if `offerId` was successfully executed. Note that we do not distinguish further between mismatched arguments/offer fields on the one hand, and an execution failure on the other. Still, a failed offer has to pay a penalty, and ultimately transaction logs explicitly mention execution failures (see `DexCommon.sol`). */

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

  /* The delegate version of `snipe` is `snipeFor`, which takes a `taker` address as additional argument. */
  function snipeFor(
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint gasreq,
    address taker
  )
    external
    returns (
      bool success,
      uint takerGot,
      uint takerGave
    )
  {
    (success, takerGot, takerGave) = generalSnipe(
      base,
      quote,
      offerId,
      takerWants,
      takerGives,
      gasreq,
      taker
    );
    deductSenderAllowance(base, quote, taker, takerGave);
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

  /* The delegate version of `snipes` is `snipesFor`, which takes a `taker` address as additional argument. */
  function snipesFor(
    address base,
    address quote,
    uint[4][] memory targets,
    address taker
  )
    external
    returns (
      uint successes,
      uint takerGot,
      uint takerGave
    )
  {
    (successes, takerGot, takerGave) = generalSnipes(
      base,
      quote,
      targets,
      taker
    );
    deductSenderAllowance(base, quote, taker, takerGave);
  }

  /* # Low-level Maker functions */

  /* ## Write Offer */

  function writeOffer(OfferPack memory ofp, bool update) internal {
    /* We check all values before packing. Otherwise, for values with a lower bound (such as `gasprice`), a check could erroneously succeed on the raw value but fail on the truncated value. */
    require(
      uint16(ofp.gasprice) == ofp.gasprice,
      "dex/writeOffer/gasprice/16bits"
    );
    /* * Check `gasreq` below limit. Implies `gasreq` at most 24 bits wide, which ensures no overflow in computation of `provision` (see below). */
    require(
      ofp.gasreq <= $$(global_gasmax("ofp.global")),
      "dex/writeOffer/gasreq/tooHigh"
    );
    /* * Make sure `gives > 0` -- division by 0 would throw in several places otherwise, and `isLive` relies on it. */
    require(ofp.gives > 0, "dex/writeOffer/gives/tooLow");
    /* * Make sure that the maker is posting a 'dense enough' offer: the ratio of `base` offered per gas consumed must be high enough. The actual gas cost paid by the taker is overapproximated by adding `offer_gasbase` to `gasreq`. */
    require(
      ofp.gives >=
        (ofp.gasreq + $$(local_offer_gasbase("ofp.local"))) *
          $$(local_density("ofp.local")),
      "dex/writeOffer/density/tooLow"
    );

    /* The following checks are for the maker's convenience only. */
    require(uint96(ofp.gives) == ofp.gives, "dex/writeOffer/gives/96bits");
    require(uint96(ofp.wants) == ofp.wants, "dex/writeOffer/wants/96bits");

    /* `gasprice` given by maker will be bounded below by internal gasprice estimate at offer write time. With a large enough overapproximation of the gasprice, the maker can regularly update their offer without paying for writes to their `balanceOf`.  */
    if (ofp.gasprice < $$(global_gasprice("ofp.global"))) {
      ofp.gasprice = $$(global_gasprice("ofp.global"));
    }

    /* Log the write offer event with some packing to save a ~1k gas. */
    {
      bytes32 writeOfferData =
        $$(
          make_writeOffer(
            [
              ["wants", "ofp.wants"],
              ["gives", "ofp.gives"],
              ["gasreq", "ofp.gasreq"],
              ["gasprice", "ofp.gasprice"],
              ["id", "ofp.id"]
            ]
          )
        );
      emit DexEvents.WriteOffer(
        ofp.base,
        ofp.quote,
        msg.sender,
        writeOfferData
      );
    }

    /* The position of the new or updated offer is found using `findPosition`. If the offer is the best one, `prev == 0`, and if it's the last in the book, `next == 0`.

       `findPosition` is only ever called here, but exists as a separate function to make the code easier to read.

    **Warning**: `findPosition` will call `better`, which may read the offer's `offerDetails`. So it is important to find the offer position _before_ we update its `offerDetail` in storage. We waste 1 read in that case but we deem that the code would get too ugly if we passed the old offerDetail as argument to `findPosition` and to `better`, just to save 1 read in that specific case.  */
    (uint prev, uint next) = findPosition(ofp);

    /* We now write the new offerDetails and remember the previous provision (0 by default, for new offers) to balance out maker's `balanceOf`. */
    uint oldProvision;
    {
      bytes32 offerDetail = offerDetails[ofp.base][ofp.quote][ofp.id];
      if (update) {
        require(
          msg.sender == $$(offerDetail_maker("offerDetail")),
          "dex/updateOffer/unauthorized"
        );
        oldProvision =
          10**9 *
          $$(offer_gasprice("ofp.oldOffer")) *
          ($$(offerDetail_gasreq("offerDetail")) +
            $$(offerDetail_overhead_gasbase("offerDetail")) +
            $$(offerDetail_offer_gasbase("offerDetail")));
      }

      /* If the offer is new, has a new gasreq, or if the Dex's `*_gasbase` configuration parameter has changed, we also update offerDetails. */
      if (
        !update ||
        $$(offerDetail_gasreq("offerDetail")) != ofp.gasreq ||
        $$(offerDetail_overhead_gasbase("offerDetail")) !=
        $$(local_overhead_gasbase("ofp.local")) ||
        $$(offerDetail_offer_gasbase("offerDetail")) !=
        $$(local_offer_gasbase("ofp.local"))
      ) {
        uint overhead_gasbase = $$(local_overhead_gasbase("ofp.local"));
        uint offer_gasbase = $$(local_offer_gasbase("ofp.local"));
        offerDetails[ofp.base][ofp.quote][ofp.id] = $$(
          make_offerDetail(
            [
              ["maker", "uint(msg.sender)"],
              ["gasreq", "ofp.gasreq"],
              ["overhead_gasbase", "overhead_gasbase"],
              ["offer_gasbase", "offer_gasbase"]
            ]
          )
        );
      }
    }

    /* With every change to an offer, a maker must deduct provisions from its `balanceOf` balance, or get some back if the updated offer requires fewer provisions. */
    {
      uint provision =
        (ofp.gasreq +
          $$(local_offer_gasbase("ofp.local")) +
          $$(local_overhead_gasbase("ofp.local"))) *
          ofp.gasprice *
          10**9;
      if (provision > oldProvision) {
        debitWei(msg.sender, provision - oldProvision);
      } else if (provision < oldProvision) {
        creditWei(msg.sender, oldProvision - provision);
      }
    }
    /* We now place the offer in the book at the position found by `findPosition`. */

    /* First, we test if the offer has moved in the book or is not currently in the book. If `!isLive(ofp.oldOffer)`, we must update its prev/next. If it is live but its prev has changed, we must also update them. Note that checking both `prev = oldPrev` and `next == oldNext` would be redundant. If either is true, then the updated offer has not changed position and there is nothing to update.

    As a note for future changes, there is a tricky edge case where `prev == oldPrev` yet the prev/next should be changed: a previously-used offer being brought back in the book, and ending with the same prev it had when it was in the book. In that case, the neighbor is currently pointing to _another_ offer, and thus must be updated. With the current code structure, this is taken care of as a side-effect of checking `!isLive`, but should be kept in mind. The same goes in the `next == oldNext` case. */
    if (!isLive(ofp.oldOffer) || prev != $$(offer_prev("ofp.oldOffer"))) {
      /* * If the offer is not the best one, we update its predecessor; otherwise we update the `best` value. */
      if (prev != 0) {
        offers[ofp.base][ofp.quote][prev] = $$(
          set_offer("offers[ofp.base][ofp.quote][prev]", [["next", "ofp.id"]])
        );
      } else {
        ofp.local = $$(set_local("ofp.local", [["best", "ofp.id"]]));
      }

      /* * If the offer is not the last one, we update its successor. */
      if (next != 0) {
        offers[ofp.base][ofp.quote][next] = $$(
          set_offer("offers[ofp.base][ofp.quote][next]", [["prev", "ofp.id"]])
        );
      }

      /* * Recall that in this branch, the offer has changed location, or is not currently in the book. If the offer is not new and already in the book, we must remove it from its previous location by stitching its previous prev/next. */
      if (update && isLive(ofp.oldOffer)) {
        ofp.local = stitchOffers(
          ofp.base,
          ofp.quote,
          $$(offer_prev("ofp.oldOffer")),
          $$(offer_next("ofp.oldOffer")),
          ofp.local
        );
      }
    }

    /* With the `prev`/`next` in hand, we finally store the offer in the `offers` map. */
    bytes32 ofr =
      $$(
        make_offer(
          [
            ["prev", "prev"],
            ["next", "next"],
            ["wants", "ofp.wants"],
            ["gives", "ofp.gives"],
            ["gasprice", "ofp.gasprice"]
          ]
        )
      );
    offers[ofp.base][ofp.quote][ofp.id] = ofr;
  }

  /* ## Find Position */
  /* `findPosition` takes a price in the form of a (`ofp.wants`,`ofp.gives`) pair, an offer id (`ofp.pivotId`) and walks the book from that offer (backward or forward) until the right position for the price is found. The position is returned as a `(prev,next)` pair, with `prev` or `next` at 0 to mark the beginning/end of the book (no offer ever has id 0).

  If prices are equal, `findPosition` will put the newest offer last. */
  function findPosition(OfferPack memory ofp)
    internal
    view
    returns (uint, uint)
  {
    uint prevId;
    uint nextId;
    uint pivotId = ofp.pivotId;
    /* Get `pivot`, optimizing for the case where pivot info is already known */
    bytes32 pivot =
      pivotId == ofp.id ? ofp.oldOffer : offers[ofp.base][ofp.quote][pivotId];

    /* In case pivotId is not an active offer, it is unusable (since it is out of the book). We default to the current best offer. If the book is empty pivot will be 0. That is handled through a test in the `better` comparison function. */
    if (!isLive(pivot)) {
      pivotId = $$(local_best("ofp.local"));
      pivot = offers[ofp.base][ofp.quote][pivotId];
    }

    /* * Pivot is better than `wants/gives`, we follow `next`. */
    if (better(ofp, pivot, pivotId)) {
      bytes32 pivotNext;
      while ($$(offer_next("pivot")) != 0) {
        uint pivotNextId = $$(offer_next("pivot"));
        pivotNext = offers[ofp.base][ofp.quote][pivotNextId];
        if (better(ofp, pivotNext, pivotNextId)) {
          pivotId = pivotNextId;
          pivot = pivotNext;
        } else {
          break;
        }
      }
      // gets here on empty book
      (prevId, nextId) = (pivotId, $$(offer_next("pivot")));

      /* * Pivot is strictly worse than `wants/gives`, we follow `prev`. */
    } else {
      bytes32 pivotPrev;
      while ($$(offer_prev("pivot")) != 0) {
        uint pivotPrevId = $$(offer_prev("pivot"));
        pivotPrev = offers[ofp.base][ofp.quote][pivotPrevId];
        if (better(ofp, pivotPrev, pivotPrevId)) {
          break;
        } else {
          pivotId = pivotPrevId;
          pivot = pivotPrev;
        }
      }

      (prevId, nextId) = ($$(offer_prev("pivot")), pivotId);
    }

    return (
      prevId == ofp.id ? $$(offer_prev("ofp.oldOffer")) : prevId,
      nextId == ofp.id ? $$(offer_next("ofp.oldOffer")) : nextId
    );
  }

  /* ## Better */
  /* The utility method `better` takes an offer represented by `ofp` and another represented by `offer1`. It returns true iff `offer1` is better or as good as `ofp`.
    "better" is defined on the lexicographic order $\textrm{price} \times_{\textrm{lex}} \textrm{density}^{-1}$.

    This means that for the same price, offers that deliver more volume per gas are taken first.
  */
  function better(
    OfferPack memory ofp,
    bytes32 offer1,
    uint offerId1
  ) internal view returns (bool) {
    if (offerId1 == 0) {
      /* Happens on empty book. Returning `false` would work as well due to specifics of `findPosition` but true is more consistent. Here we just want to avoid reading `offerDetail[...][0]` for nothing. */
      return true;
    }
    uint wants1 = $$(offer_wants("offer1"));
    uint gives1 = $$(offer_gives("offer1"));
    uint wants2 = ofp.wants;
    uint gives2 = ofp.gives;
    uint weight1 = wants1 * gives2;
    uint weight2 = wants2 * gives1;
    if (weight1 == weight2) {
      /* To save gas, instead of giving the `gasreq1` argument directly, we provided a path to it (with `offerDetails` and `offerid1`). If necessary (ie. if the prices `wants1/gives1` and `wants2/gives2` are the same), we read storage to get `gasreq2`. */
      uint gasreq1 =
        $$(offerDetail_gasreq("offerDetails[ofp.base][ofp.quote][offerId1]"));
      uint gasreq2 = ofp.gasreq;
      return (gives1 * gasreq2 >= gives2 * gasreq1);
    } else {
      return weight1 < weight2;
    }
  }

  /* # Low-level Taker functions */

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
    require(uint160(takerWants) == takerWants, "dex/mOrder/takerWants/160bits");

    /* `SingleOrder` is defined in `DexCommon.sol` and holds information for ordering the execution of one offer. */
    DC.SingleOrder memory sor;
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

    /* Over the course of the market order, a penalty reserved for `msg.sender` has accumulated in `mor.totalPenalty`. No actual transfers have occured yet -- all the ethers given by the makers as provision are owned by the Dex. `sendPenalty` finally gives the accumulated penalty to `msg.sender`. */
    sendPenalty(mor.totalPenalty);
    //+clear+
    return (mor.totalGot, mor.totalGave);
  }

  /* ### Recursive market order function */
  //+clear+
  function internalMarketOrder(
    MultiOrder memory mor,
    DC.SingleOrder memory sor,
    bool proceed
  ) internal {
    /* #### Case 1 : End of order */
    /* We execute the offer currently stored in `sor`. */
    if (proceed && sor.wants > 0 && sor.offerId > 0) {
      bool success; // execution success/failure
      uint gasused; // gas used by `makerTrade`
      bytes32 makerData; // data returned by maker
      bytes32 errorCode; // internal dex error code
      /* `executed` is false if offer could not be executed against 2nd and 3rd argument of execute. Currently, we interrupt the loop and let the taker leave with less than they asked for (but at a correct price). We could also revert instead of breaking; this could be a configurable flag for the taker to pick. */
      // reduce stack size for recursion

      bool executed; // offer execution attempted or not

      /* Load additional information about the offer. We don't do it earlier to save one storage read in case `proceed` was false. */
      sor.offerDetail = offerDetails[sor.base][sor.quote][sor.offerId];

      /* `execute` will adjust `sor.wants`,`sor.gives`, and may attempt to execute the offer if its price is low enough. It is crucial that an error due to `taker` triggers a revert. That way, `!success && !executed` means there was no execution attempt, and `!success && executed` means the failure is the maker's fault. */
      /* Post-execution, `sor.wants`/`sor.gives` reflect how much was sent/taken by the offer. We will need it after the recursive call, so we save it in local variables. Same goes for `offerId`, `sor.offer` and `sor.offerDetail`. */
      (success, executed, gasused, makerData, errorCode) = execute(mor, sor);

      {
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
      }

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

      /* `applyFee` extracts the fee from the taker, proportional to the amount purchased */
      applyFee(mor, sor);

      /* In an FTD, amounts have been lent by each offer's maker to the taker. We now call the taker. This is a noop in an FMD. */
      executeEnd(mor, sor);
    }
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
    DC.SingleOrder memory sor;
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

    /* Over the course of the snipes order, a penalty reserved for `msg.sender` has accumulated in `mor.totalPenalty`. No actual transfers have occured yet -- all the ethers given by the makers as provision are owned by the Dex. `sendPenalty` finally gives the accumulated penalty to `msg.sender`. */
    sendPenalty(mor.totalPenalty);
    //+clear+
    return (mor.successCount, mor.totalGot, mor.totalGave);
  }

  /* ### Recursive snipes function */
  //+clear+
  function internalSnipes(
    MultiOrder memory mor,
    DC.SingleOrder memory sor,
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
          "dex/snipes/takerWants/96bits"
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
      /* `applyFee` extracts the fee from the taker, proportional to the amount purchased */
      applyFee(mor, sor);
      /* In an FTD, amounts have been lent by each offer's maker to the taker. We now call the taker. This is a noop in an FMD. */
      executeEnd(mor, sor);
    }
  }

  /* ## Execute */
  /* This function will compare `sor.wants` `sor.gives` with `sor.offer.wants` and `sor.offer.gives`. If the price of the offer is low enough, an execution will be attempted (with volume limited by the offer's advertised volume).

     Summary of the meaning of the return values:
    * `gasused` is the gas consumed by the execution
    * `makerData` is the data returned after executing the offer
    * `errorCode` is the internal dex error code
    * `success -> executed`
    * `success && executed`: offer has succeeded
    * `!success && executed`: offer has failed
    * `!success && !executed`: offer has not been executed */
  function execute(MultiOrder memory mor, DC.SingleOrder memory sor)
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

   **Historical note**: prices used to be rounded up (`makerWouldWant = product/offer.gives + (product % offer.gives == 0 ? 0 : 1)`) because partially filled offers used to remain on the book. A snipe which names an offer by its id also specifies its price in the form of a `(wants,gives)` pair to be compared to the offers' `(wants,gives)`. When a snipe can specifies a wants and a gives, it accepts any offer price better than `wants/gives`.

   Now consider an order $r$ for the offer $o$. If $o$ is partially consumed into $o'$ before $r$ is mined, we still want $r$ to succeed (as long as $o'$ has enough volume). But `wants` and `gives` of $o$ are not equal to `wants` and `gives` of $o'$. Worse: their ratios are not equal, due to rounding errors.

   Our solution was to make sure that the price of a partially filled offer could only improve. To do that, we rounded up the amount required by the maker.
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

    /* The flashloan is executed by call to `FLASHLOANER`. If the call reverts, it means the maker failed to send back `sor.wants` `base` to the taker. Notes :
     * `msg.sender` is the Dex itself in those calls -- all operations related to the actual caller should be done outside of this call.
     * any spurious exception due to an error in Dex code will be falsely blamed on the Maker, and its provision for the offer will be unfairly taken away.
     */
    bytes memory retdata;
    (success, retdata) = address(this).call(
      abi.encodeWithSelector(FLASHLOANER, sor, mor.taker)
    );

    /* `success` is true: trade is complete */
    if (success) {
      mor.successCount += 1;
      /* In case of success, `retdata` encodes the gas used by the offer. */
      gasused = abi.decode(retdata, (uint));

      emit DexEvents.Success(
        sor.base,
        sor.quote,
        sor.offerId,
        mor.taker,
        sor.wants,
        sor.gives
      );

      /* If configured to do so, the Dex notifies an external contract that a successful trade has taken place. */
      if ($$(global_notify("sor.global")) > 0) {
        IDexMonitor($$(global_monitor("sor.global"))).notifySuccess(
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
      /* Note that in the `if`s, the literals are bytes32 (stack values), while as revert arguments, they are strings (memory pointers). */
      if (
        errorCode == "dex/makerRevert" || errorCode == "dex/makerTransferFail"
      ) {
        mor.failCount += 1;

        emit DexEvents.MakerFail(
          sor.base,
          sor.quote,
          sor.offerId,
          mor.taker,
          sor.wants,
          sor.gives,
          errorCode,
          makerData
        );

        /* If configured to do so, the Dex notifies an external contract that a failed trade has taken place. */
        if ($$(global_notify("sor.global")) > 0) {
          IDexMonitor($$(global_monitor("sor.global"))).notifyFail(
            sor,
            mor.taker
          );
        }
        /* It is crucial that any error code which indicates an error caused by the taker triggers a revert, because functions that call `execute` consider that `execute && !success` should be blamed on the maker. */
      } else if (errorCode == "dex/notEnoughGasForMakerTrade") {
        revert("dex/notEnoughGasForMakerTrade");
      } else if (errorCode == "dex/takerFailToPayMaker") {
        revert("dex/takerFailToPayMaker");
      } else {
        /* This code must be unreachable. **Danger**: if a well-crafted offer/maker pair can force a revert of FLASHLOANER, the Dex will be stuck. */
        revert("dex/swapError");
      }
    }

    /* Delete the offer. The last argument indicates whether the offer should be stripped of its provision (yes if execution failed, no otherwise). We delete offers whether the amount remaining on offer is > density or not for the sake of uniformity (code is much simpler). We also expect prices to move often enough that the maker will want to update their price anyway. To simulate leaving the remaining volume in the offer, the maker can program their `makerPosthook` to `updateOffer` and put the remaining volume back in. */
    if (executed) {
      dirtyDeleteOffer(sor.base, sor.quote, sor.offerId, sor.offer, !success);
    }
  }

  /* ## Post execute */
  /* After executing an offer (whether in a market order or in snipes), we
     1. FTD only, if execution successful: transfer the correct amount back to the maker.
     2. If offer was executed: call the maker's posthook and sum the total gas used. In FTD, the posthook is called with the amount already in the maker's hands.
     3. If offer failed: sum total penalty due to taker and give remainder to maker.
   */
  function postExecute(
    MultiOrder memory mor,
    DC.SingleOrder memory sor,
    bool success,
    uint gasused,
    bytes32 makerData,
    bytes32 errorCode
  ) internal {
    if (success) {
      executeCallback(mor, sor);
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
      mor.totalPenalty += applyPenalty(
        $$(global_gasprice("sor.global")),
        gasused,
        sor.offer,
        sor.offerDetail,
        mor.failCount
      );
    }
  }

  /* ## Maker Posthook */
  function makerPosthook(
    DC.SingleOrder memory sor,
    uint gasLeft,
    bool success,
    bytes32 makerData,
    bytes32 errorCode
  ) internal returns (uint gasused) {
    /* At this point, errorCode can only be "dex/makerRevert" or "dex/makerTransferFail" */
    bytes memory cd =
      abi.encodeWithSelector(
        IMaker.makerPosthook.selector,
        sor,
        DC.OrderResult({
          success: success,
          makerData: makerData,
          errorCode: errorCode
        })
      );

    /* Calls an external function with controlled gas expense. A direct call of the form `(,bytes memory retdata) = maker.call{gas}(selector,...args)` enables a griefing attack: the maker uses half its gas to write in its memory, then reverts with that memory segment as argument. After a low-level call, solidity automaticaly copies `returndatasize` bytes of `returndata` into memory. So the total gas consumed to execute a failing offer could exceed `gasreq`. This yul call only retrieves the first byte of the maker's `returndata`. */
    bytes memory retdata = new bytes(32);

    address maker = $$(offerDetail_maker("sor.offerDetail"));

    uint oldGas = gasleft();
    /* We let the maker pay for the overhead of checking remaining gas and making the call. So the `require` below is just an approximation: if the overhead of (`require` + cost of `CALL`) is $h$, the maker will receive at worst $\textrm{gasreq} - \frac{63h}{64}$ gas. */
    if (!(oldGas - oldGas / 64 >= gasLeft)) {
      revert("dex/notEnoughGasForMakerPosthook");
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

  /* # Low-level offer deletion */

  /* When an offer is deleted, it is marked as such by setting `gives` to 0. Note that provision accounting in the Dex aims to minimize writes. Each maker `fund`s the Dex to increase its balance. When an offer is created/updated, we compute how much should be reserved to pay for possible penalties. That amount can always be recomputed with `offer.gasprice * (offerDetail.gasreq + offerDetail.overhead_gasbase + offerDetail.offer_gasbase)`. The balance is updated to reflect the remaining available ethers.

     Now, when an offer is deleted, the offer can stay provisioned, or be `deprovision`ed. In the latter case, we set `gasprice` to 0, which induces a provision of 0. */
  function dirtyDeleteOffer(
    address base,
    address quote,
    uint offerId,
    bytes32 offer,
    bool deprovision
  ) internal {
    offer = $$(set_offer("offer", [["gives", 0]]));
    if (deprovision) {
      offer = $$(set_offer("offer", [["gasprice", 0]]));
    }
    offers[base][quote][offerId] = offer;
  }

  /* Post-trade, `applyFee` reaches back into the taker's pocket and extract a fee on the total amount of `sor.base` transferred to them. */
  function applyFee(MultiOrder memory mor, DC.SingleOrder memory sor) internal {
    if (mor.totalGot > 0 && $$(local_fee("sor.local")) > 0) {
      uint concreteFee = (mor.totalGot * $$(local_fee("sor.local"))) / 10_000;
      mor.totalGot -= concreteFee;
      bool success = transferToken(sor.base, mor.taker, vault, concreteFee);
      require(success, "dex/takerFailToPayDex");
    }
  }

  /* # Penalties */
  /* Offers are just promises. They can fail. Penalty provisioning discourages from failing too much: we ask makers to provision more ETH than the expected gas cost of executing their offer and penalize them accoridng to wasted gas.

     Under normal circumstances, we should expect to see bots with a profit expectation dry-running offers locally and executing `snipe` on failing offers, collecting the penalty. The result should be a mostly clean book for actual takers (i.e. a book with only successful offers).

     **Incentive issue**: if the gas price increases enough after an offer has been created, there may not be an immediately profitable way to remove the fake offers. In that case, we count on 3 factors to keep the book clean:
     1. Gas price eventually comes down.
     2. Other market makers want to keep the Dex attractive and maintain their offer flow.
     3. Dex governance (who may collect a fee) wants to keep the Dex attractive and maximize exchange volume.

  //+clear+
  /* After an offer failed, part of its provision is given back to the maker and the rest is stored to be sent to the taker after the entire order completes. In `applyPenalty`, we _only_ credit the maker with its excess provision. So it looks like the maker is gaining something. In fact they're just getting back a fraction of what they provisioned earlier.
  /*
     Penalty application summary:

   * If the transaction was a success, we entirely refund the maker and send nothing to the taker.
   * Otherwise, the maker loses the cost of `gasused + overhead_gasbase/n + offer_gasbase` gas, where `n` is the number of failed offers. The gas price is estimated by `gasprice`.
   * To create the offer, the maker had to provision for `gasreq + overhead_gasbase/n + offer_gasbase` gas at a price of `offer.gasprice`.
   * We do not consider the tx.gasprice.
   * `offerDetail.gasbase` and `offer.gasprice` are the values of the Dex parameters `config.*_gasbase` and `config.gasprice` when the offer was created. Without caching those values, the provision set aside could end up insufficient to reimburse the maker (or to retribute the taker).
   */
  function applyPenalty(
    uint gasprice,
    uint gasused,
    bytes32 offer,
    bytes32 offerDetail,
    uint failCount
  ) internal returns (uint) {
    uint provision =
      10**9 *
        $$(offer_gasprice("offer")) *
        ($$(offerDetail_gasreq("offerDetail")) +
          $$(offerDetail_overhead_gasbase("offerDetail")) +
          $$(offerDetail_offer_gasbase("offerDetail")));

    /* We take as gasprice min(offer.gasprice,config.gasprice) */
    if ($$(offer_gasprice("offer")) < gasprice) {
      gasprice = $$(offer_gasprice("offer"));
    }

    /* We set `gasused = min(gasused,gasreq)` since `gasreq < gasused` is possible e.g. with `gasreq = 0` (all calls consume nonzero gas). */
    if ($$(offerDetail_gasreq("offerDetail")) < gasused) {
      gasused = $$(offerDetail_gasreq("offerDetail"));
    }

    /* As an invariant, `applyPenalty` is only called when `executed && !success`, and thus when `failCount > 0`. */
    uint penalty =
      10**9 *
        gasprice *
        (gasused +
          $$(offerDetail_overhead_gasbase("offerDetail")) /
          failCount +
          $$(offerDetail_offer_gasbase("offerDetail")));

    /* Here we write to storage the new maker balance. This occurs _after_ possible reentrant calls. How do we know we're not crediting twice the same amounts? Because the `offer`'s provision was set to 0 in storage (through `dirtyDeleteOffer`) before the reentrant calls. In this function, we are working with cached copies of the offer as it was before it was consumed. */
    creditWei($$(offerDetail_maker("offerDetail")), provision - penalty);

    return penalty;
  }

  function sendPenalty(uint amount) internal {
    if (amount > 0) {
      bool noRevert;
      (noRevert, ) = msg.sender.call{gas: 0, value: amount}("");
    }
  }

  /* # Get/set configuration and Dex state */

  function config(address base, address quote)
    public
    returns (bytes32 _global, bytes32 _local)
  {
    _global = global;
    _local = locals[base][quote];
    if ($$(global_useOracle("_global")) > 0) {
      (uint gasprice, uint density) =
        IDexMonitor($$(global_monitor("_global"))).read(base, quote);
      _global = $$(set_global("_global", [["gasprice", "gasprice"]]));
      _local = $$(set_local("_local", [["density", "density"]]));
    }
  }

  /* ## Locals */
  /* ### `active` */
  function activate(
    address base,
    address quote,
    uint fee,
    uint density,
    uint overhead_gasbase,
    uint offer_gasbase
  ) public {
    authOnly();
    locals[base][quote] = $$(set_local("locals[base][quote]", [["active", 1]]));
    setFee(base, quote, fee);
    setDensity(base, quote, density);
    setGasbase(base, quote, overhead_gasbase, offer_gasbase);
    emit DexEvents.SetActive(base, quote, true);
  }

  function deactivate(address base, address quote) public {
    authOnly();
    locals[base][quote] = $$(set_local("locals[base][quote]", [["active", 0]]));
    emit DexEvents.SetActive(base, quote, true);
  }

  /* ### `fee` */
  function setFee(
    address base,
    address quote,
    uint value
  ) public {
    authOnly();
    /* `fee` is in basis points, i.e. in percents of a percent. */
    require(value <= 500, "dex/config/fee/<=500"); // at most 5%
    locals[base][quote] = $$(
      set_local("locals[base][quote]", [["fee", "value"]])
    );
    emit DexEvents.SetFee(base, quote, value);
  }

  /* ### `density` */
  /* Useless if `global.useOracle != 0` */
  function setDensity(
    address base,
    address quote,
    uint value
  ) public {
    authOnly();
    /* Checking the size of `density` is necessary to prevent overflow when `density` is used in calculations. */
    require(uint32(value) == value, "dex/config/density/32bits");
    //+clear+
    locals[base][quote] = $$(
      set_local("locals[base][quote]", [["density", "value"]])
    );
    emit DexEvents.SetDensity(base, quote, value);
  }

  /* ### `gasbase` */
  function setGasbase(
    address base,
    address quote,
    uint overhead_gasbase,
    uint offer_gasbase
  ) public {
    authOnly();
    /* Checking the size of `*_gasbase` is necessary to prevent a) data loss when `*_gasbase` is copied to an `OfferDetail` struct, and b) overflow when `*_gasbase` is used in calculations. */
    require(
      uint24(overhead_gasbase) == overhead_gasbase,
      "dex/config/overhead_gasbase/24bits"
    );
    require(
      uint24(offer_gasbase) == offer_gasbase,
      "dex/config/offer_gasbase/24bits"
    );
    //+clear+
    locals[base][quote] = $$(
      set_local(
        "locals[base][quote]",
        [
          ["offer_gasbase", "offer_gasbase"],
          ["overhead_gasbase", "overhead_gasbase"]
        ]
      )
    );
    emit DexEvents.SetGasbase(overhead_gasbase, offer_gasbase);
  }

  /* ## Globals */
  /* ### `kill` */
  function kill() public {
    authOnly();
    global = $$(set_global("global", [["dead", 1]]));
    emit DexEvents.Kill();
  }

  /* ### `gasprice` */
  /* Useless if `global.useOracle is != 0` */
  function setGasprice(uint value) public {
    authOnly();
    /* Checking the size of `gasprice` is necessary to prevent a) data loss when `gasprice` is copied to an `OfferDetail` struct, and b) overflow when `gasprice` is used in calculations. */
    require(uint16(value) == value, "dex/config/gasprice/16bits");
    //+clear+

    global = $$(set_global("global", [["gasprice", "value"]]));
    emit DexEvents.SetGasprice(value);
  }

  /* ### `gasmax` */
  function setGasmax(uint value) public {
    authOnly();
    /* Since any new `gasreq` is bounded above by `config.gasmax`, this check implies that all offers' `gasreq` is 24 bits wide at most. */
    require(uint24(value) == value, "dex/config/gasmax/24bits");
    //+clear+
    global = $$(set_global("global", [["gasmax", "value"]]));
    emit DexEvents.SetGasmax(value);
  }

  function setGovernance(address value) public {
    authOnly();
    governance = value;
    emit DexEvents.SetGovernance(value);
  }

  function setVault(address value) public {
    authOnly();
    vault = value;
    emit DexEvents.SetVault(value);
  }

  function setMonitor(address value) public {
    authOnly();
    global = $$(set_global("global", [["monitor", "value"]]));
    emit DexEvents.SetMonitor(value);
  }

  function authOnly() internal view {
    require(
      msg.sender == governance || msg.sender == address(this),
      "dex/unauthorized"
    );
  }

  function setUseOracle(bool value) public {
    authOnly();
    if (value) {
      global = $$(set_global("global", [["useOracle", 1]]));
    } else {
      global = $$(set_global("global", [["useOracle", 0]]));
    }
    emit DexEvents.SetUseOracle(value);
  }

  function setNotify(bool value) public {
    authOnly();
    if (value) {
      global = $$(set_global("global", [["notify", 1]]));
    } else {
      global = $$(set_global("global", [["notify", 0]]));
    }
    emit DexEvents.SetNotify(value);
  }

  /* # Maker debit/credit utility functions */

  function debitWei(address maker, uint amount) internal {
    uint makerBalance = balanceOf[maker];
    require(makerBalance >= amount, "dex/insufficientProvision");
    balanceOf[maker] = makerBalance - amount;
    emit DexEvents.Debit(maker, amount);
  }

  function creditWei(address maker, uint amount) internal {
    balanceOf[maker] += amount;
    emit DexEvents.Credit(maker, amount);
  }

  /* # Delegation public functions */

  /* Adapted from [Uniswap v2 contract](https://github.com/Uniswap/uniswap-v2-core/blob/55ae25109b7918565867e5c39f1e84b7edd19b2a/contracts/UniswapV2ERC20.sol#L81) */
  function permit(
    address base,
    address quote,
    address owner,
    address spender,
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    require(deadline >= block.timestamp, "dex/permit/expired");

    uint nonce = nonces[owner]++;
    bytes32 digest =
      keccak256(
        abi.encodePacked(
          "\x19\x01",
          DOMAIN_SEPARATOR,
          keccak256(
            abi.encode(
              PERMIT_TYPEHASH,
              base,
              quote,
              owner,
              spender,
              value,
              nonce,
              deadline
            )
          )
        )
      );
    address recoveredAddress = ecrecover(digest, v, r, s);
    require(
      recoveredAddress != address(0) && recoveredAddress == owner,
      "dex/permit/invalidSignature"
    );

    allowances[base][quote][owner][spender] = value;
    emit DexEvents.Approval(base, quote, owner, spender, value);
  }

  function approve(
    address base,
    address quote,
    address spender,
    uint value
  ) external returns (bool) {
    allowances[base][quote][msg.sender][spender] = value;
    emit DexEvents.Approval(base, quote, msg.sender, spender, value);
    return true;
  }

  /* # Misc. low-level functions */

  /* Connect the predecessor and sucessor of `id` through their `next`/`prev` pointers. For more on the book structure, see `DexCommon.sol`. This step is not necessary during a market order, so we only call `dirtyDeleteOffer`.

  **Warning**: calling with `worseId = 0` will set `betterId` as the best. So with `worseId = 0` and `betterId = 0`, it sets the book to empty and loses track of existing offers.

  **Warning**: may make memory copy of `local.best` stale. Returns new `local`. */
  function stitchOffers(
    address base,
    address quote,
    uint worseId,
    uint betterId,
    bytes32 local
  ) internal returns (bytes32) {
    if (worseId != 0) {
      offers[base][quote][worseId] = $$(
        set_offer("offers[base][quote][worseId]", [["next", "betterId"]])
      );
    } else {
      local = $$(set_local("local", [["best", "betterId"]]));
    }

    if (betterId != 0) {
      offers[base][quote][betterId] = $$(
        set_offer("offers[base][quote][betterId]", [["prev", "worseId"]])
      );
    }

    return local;
  }

  /* Used by `*For` functions, its both checks that `msg.sender` was allowed to use the taker's funds, and decreases the former's allowance. */
  function deductSenderAllowance(
    address base,
    address quote,
    address owner,
    uint amount
  ) internal {
    uint allowed = allowances[base][quote][owner][msg.sender];
    require(allowed > amount, "dex/lowAllowance");
    allowances[base][quote][owner][msg.sender] = allowed - amount;
  }

  /* # Flashloans */
  //+clear+
  /* ## Flashloan */
  /*
     `flashloan` is for the 'normal' mode of operation. It:
     1. Flashloans `takerGives` `quote` from the taker to the maker and returns false if the loan fails.
     2. Runs `offerDetail.maker`'s `execute` function.
     3. Returns the result of the operations, with optional makerData to help the maker debug.
   */
  function flashloan(DC.SingleOrder calldata sor, address taker)
    external
    returns (uint gasused)
  {
    /* `flashloan` must be used with a call (hence the `external` modifier) so its effect can be reverted. But a call from the outside would be fatal. */
    require(msg.sender == address(this), "dex/flashloan/protected");
    /* the transfer from taker to maker must be in this function
       so that any issue with the maker also reverts the flashloan */
    if (
      transferToken(
        sor.quote,
        taker,
        $$(offerDetail_maker("sor.offerDetail")),
        sor.gives
      )
    ) {
      gasused = makerExecute(sor, taker);
    } else {
      innerRevert([bytes32("dex/takerFailToPayMaker"), "", ""]);
    }
  }

  /* ## Inverted Flashloan */
  /*
     `invertedFlashloan` is for the 'arbitrage' mode of operation. It:
     0. Calls the maker's `execute` function. If successful (tokens have been sent to taker):
     2. Runs `taker`'s `execute` function.
     4. Returns the results ofthe operations, with optional makerData to help the maker debug.

     There are two ways to do the flashloan:
     1. balanceOf before/after
     2. run transferFrom ourselves.

     ### balanceOf pros:
       * maker may `transferFrom` another address they control; saves gas compared to dex's `transferFrom`
       * maker does not need to `approve` dex

     ### balanceOf cons
       * if the ERC20 transfer method has a callback to receiver, the method does not work (the receiver can set its balance to 0 during the callback)
       * if the taker is malicious, they can analyze the maker code. If the maker goes on any dex2, they may execute code provided by the taker. This would reduce the taker balance and make the maker fail. So the taker could steal the maker's balance.

    We choose `transferFrom`.
    */

  function invertedFlashloan(DC.SingleOrder calldata sor, address taker)
    external
    returns (uint gasused)
  {
    /* `invertedFlashloan` must be used with a call (hence the `external` modifier) so its effect can be reverted. But a call from the outside would be fatal. */
    require(msg.sender == address(this), "dex/invertedFlashloan/protected");
    gasused = makerExecute(sor, taker);
  }

  /* ## Maker Execute */

  function makerExecute(DC.SingleOrder calldata sor, address taker)
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
      innerRevert([bytes32("dex/notEnoughGasForMakerTrade"), "", ""]);
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
      innerRevert([bytes32("dex/makerRevert"), bytes32(gasused), makerData]);
    }

    bool transferSuccess = transferToken(sor.base, maker, taker, sor.wants);

    if (!transferSuccess) {
      innerRevert(
        [bytes32("dex/makerTransferFail"), bytes32(gasused), makerData]
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

  /* # Abstract functions */

  function executeEnd(MultiOrder memory mor, DC.SingleOrder memory sor)
    internal
    virtual;

  function executeCallback(MultiOrder memory mor, DC.SingleOrder memory sor)
    internal
    virtual;
}

/* # FMD and FTD instanciations of Dex */

contract FMD is Dex {
  constructor(uint gasprice, uint gasmax) Dex(gasprice, gasmax, true, "FMD") {}

  function executeEnd(MultiOrder memory mor, DC.SingleOrder memory sor)
    internal
    override
  {}

  function executeCallback(MultiOrder memory mor, DC.SingleOrder memory sor)
    internal
    override
  {}
}

contract FTD is Dex {
  constructor(uint gasprice, uint gasmax) Dex(gasprice, gasmax, false, "FTD") {}

  // execute taker trade
  function executeEnd(MultiOrder memory mor, DC.SingleOrder memory sor)
    internal
    override
  {
    ITaker(mor.taker).takerTrade(
      sor.base,
      sor.quote,
      mor.totalGot,
      mor.totalGave
    );
  }

  /* We use `transferFrom` with takers (instead of checking `balanceOf` before/after the call) for the following reason we want the taker to be awaken after all loans have been made, so either
     1. The taker gets a list of all makers and loops through them to pay back, or
     2. we call a new taker method "payback" after returning from each maker call, or
     3. we call transferFrom after returning from each maker call

So :
   1. Would mean accumulating a list of all makers, which would make the market order code too complex
   2. Is OK, but has an extra CALL cost on top of the token transfer, one for each maker. This is unavoidable anyway when calling makerTrade (since the maker must be able to execute arbitrary code at that moment), but we can skip it here.
   3. Is the cheapest, but it has the drawbacks of `transferFrom`: money must end up owned by the taker, and taker needs to `approve` Dex
   */
  function executeCallback(MultiOrder memory mor, DC.SingleOrder memory sor)
    internal
    override
  {
    bool success =
      transferToken(
        sor.quote,
        mor.taker,
        $$(offerDetail_maker("sor.offerDetail")),
        sor.gives
      );
    require(success, "dex/takerFailToPayMaker");
  }
}
