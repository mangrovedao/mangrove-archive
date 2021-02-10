// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
// Encode structs
pragma abicoder v2;
// ERC, Maker, Taker interfaces
import "./interfaces.sol";
// Types common to main Dex contract and DexLib
import {DexCommon as DC, DexEvents, IDexMonitor} from "./DexCommon.sol";
// The purpose of DexLib is to keep Dex under the [Spurious Dragon](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-170.md) 24kb limit.
import "./DexLib.sol";

/* # State variables
   This contract describes an orderbook-based exchange ("Dex") where market makers *do not have to provision their offer*. See `DexCommon.sol` for a longer introduction. In a nutshell: each offer created by a maker specifies an address (`maker`) to call upon offer execution by a taker. The Dex transfers the amount to be paid by the taker to the maker, calls the maker, attempts to transfer the amount promised by the maker to the taker, and reverts if it cannot.


   One Dex instance is only an `OFR_TOKEN`/`REQ_TOKEN` market. For a `REQ_TOKEN`/`OFR_TOKEN` market, one should create another Dex instance with the two tokens swapped.

   The state variables are:
 */

abstract contract Dex {
  /* Holds data about orders in a struct, used by `marketOrder` and `internalSnipes` (and some of their nested functions) to avoid stack too deep errors. */
  struct MultiOrder {
    uint initialWants;
    uint initialGives;
    uint totalGot;
    uint totalGave;
    uint totalPenalty;
    // used as #successes in internalSnipes
    uint snipeSuccesses;
    address taker;
  }

  /* The governance address */
  address public governance;
  address public vault;

  /* The signature of the low-level swapping function. */
  bytes4 immutable FLASHLOANER;

  /* * An offer `id` is defined by two structs, `Offer` and `OfferDetail`, defined in `DexCommon.sol`.
   * `offers[id]` contains pointers to the `prev`ious (better) and `next` (worse) offer in the book, as well as the price and volume of the offer (in the form of two absolute quantities, `wants` and `gives`).
   * `offerDetails[id]` contains the market maker's address (`maker`), the amount of gas required by the offer (`gasreq`) as well cached values for the global `gasbase` and `gasprice` when the offer got created (see `DexCommon` for more on `gasbase` and `gasprice`).
   */
  mapping(address => mapping(address => mapping(uint => bytes32)))
    public offers;
  mapping(address => mapping(address => mapping(uint => bytes32)))
    public offerDetails;

  bytes32 public global;
  mapping(address => mapping(address => bytes32)) public locals;

  /* * Makers provision their possible penalties in the `balanceOf` mapping.

       Offers specify the amount of gas they require for successful execution (`gasreq`). To minimize book spamming, market makers must provision a *penalty*, which depends on their `gasreq`. This provision is deducted from their `balanceOf`. If an offer fails, part of that provision is given to the taker, as compensation. The exact amount depends on the gas used by the offer before failing.

       The Dex keeps track of their available balance in the `balanceOf` map, which is decremented every time a maker creates a new offer (new offer creation is in `DexLib`, see `writeOffer`), and modified on offer updates/cancelations/takings.
   */
  mapping(address => uint) public balanceOf;

  /*
  # Dex Constructor

  A new Dex instance manages one side of a book; it offers `OFR_TOKEN` in return for `REQ_TOKEN`. To initialize a new instance, the deployer must provide initial configuration (see `DexCommon.sol` for more on configuration parameters):
  */
  constructor(
    uint _gasprice,
    uint gasmax,
    /* determines whether the taker or maker does the flashlend */
    bool takerLends,
    string memory contractName
  ) {
    emit DexEvents.NewDex();

    governance = msg.sender;
    emit DexEvents.SetGovernance(msg.sender);

    setVault(msg.sender);
    setGasprice(_gasprice);
    setGasmax(gasmax);
    /* In a 'normal' mode of operation, takers lend the liquidity to the maker. */
    /* In an 'arbitrage' mode of operation, takers come ask the makers for liquidity. */
    FLASHLOANER = takerLends
      ? DexLib.flashloan.selector
      : DexLib.invertedFlashloan.selector;

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

  /*
  # Gatekeeping

  Gatekeeping functions start with `require` and are safety checks called in various places.
  */

  /* `requireNoReentrancyLock` protects modifying the book while an order is in progress. */
  function unlockedOnly(bytes32 local) internal pure {
    require($$(loc_lock("local")) == 0, "dex/reentrancyLocked");
  }

  /* * <a id="Dex/definition/requireLiveDex"></a>
     In case of emergency, the Dex can be `kill()`ed. It cannot be resurrected. When a Dex is dead, the following operations are disabled :
       * Executing an offer
       * Sending ETH to the Dex (the normal way, usual shenanigans are possible)
       * Creating a new offerX
   */
  function requireLiveDex(bytes32 _global) internal pure {
    require($$(glo_dead("_global")) == 0, "dex/dead");
  }

  /* TODO documentation */
  function requireActiveMarket(bytes32 _global, bytes32 _local) internal pure {
    requireLiveDex(_global);
    require($$(loc_active("_local")) > 0, "dex/inactive");
  }

  /* # Maker operations
     ## New Offer */
  //+clear+
  /* In the Dex, makers and takers call separate functions. Market makers call `newOffer` to fill the book, and takers call functions such as `marketOrder` to consume it.  */
  //+clear+

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

  /* The function `newOffer` is for market makers only; no match with the existing book is done. Makers specify how much `REQ_TOKEN` they `want` and how much `OFR_TOKEN` they are willing to `give`. They also specify how much gas should be given when executing their offer.

 _`gasreq` will determine the penalty provision set aside by the Dex from the market maker's `balanceOf` balance._

  Offers are always inserted at the correct place in the book (for more on the book data structure, see `DexCommon.sol`). This requires walking through offers to find the correct insertion point. As in [Oasis](https://github.com/daifoundation/maker-otc/blob/master/src/matching_market.sol#L129), Makers should find the id of an offer close to theirs and provide it as `pivotId`.

  An offer cannot be inserted in a closed market, nor when reentrancy is disabled.

  No more than 2^32^-1 offers can ever be created.

  The [actual content of the function](#DexLib/definition/newOffer) is in `DexLib`, due to size limitations.
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
    OfferPack memory ofp;
    (ofp.global, ofp.local) = getConfig(base, quote);
    unlockedOnly(ofp.local);
    requireActiveMarket(ofp.global, ofp.local);

    ofp.id = 1 + $$(loc_lastId("ofp.local"));
    require(uint24(ofp.id) == ofp.id, "dex/offerIdOverflow");

    ofp.local = $$(loc_set("ofp.local", [["lastId", "ofp.id"]]));

    ofp.base = base;
    ofp.quote = quote;
    ofp.wants = wants;
    ofp.gives = gives; // an offer id must never be 0
    ofp.gasreq = gasreq;
    ofp.gasprice = gasprice;
    ofp.pivotId = pivotId;

    /* writeOffer may modify ofp.local.best */
    writeOffer(ofp, false);
    locals[ofp.base][ofp.quote] = ofp.local;
    return ofp.id;
  }

  /* ## Retract Offer */
  //+clear+
  /* `retractOffer` with `_delete == false` takes the offer `offerId` out of the book. However, `_delete == true` also clears out the offer's entry in `offers` and `offerDetails` -- a deleted offer cannot be resurrected. */
  function retractOffer(
    address base,
    address quote,
    uint offerId,
    bool _delete
  ) external {
    (, bytes32 local) = getConfig(base, quote);
    unlockedOnly(local);
    bytes32 offer = offers[base][quote][offerId];
    bytes32 offerDetail = offerDetails[base][quote][offerId];
    require(
      msg.sender == $$(od_maker("offerDetail")),
      "dex/retractOffer/unauthorized"
    );

    /* An important invariant is that an offer is 'live' iff (gives > 0) iff (the offer is in the book). Here, we are about to *un-live* the offer, so we start by taking it out of the book. Note that unconditionally calling `stitchOffers` would break the book since it would connect offers that may have moved. */
    if (isLive(offer)) {
      bytes32 oldLocal = local;
      local = stitchOffers(
        base,
        quote,
        $$(o_prev("offer")),
        $$(o_next("offer")),
        local
      );
      if (oldLocal != local) {
        locals[base][quote] = local;
      }
      if (!_delete) {
        // set `offer.gives` to 0
        dirtyDeleteOffer(base, quote, offerId, offer, false);
      }
    }

    if (_delete) {
      /* Without a cast to `uint`, the operations convert to the larger type (gasprice) and may truncate */
      uint provision =
        10**9 *
          $$(o_gasprice("offer")) * //gasprice is 0 if offer was deprovisioned
          ($$(od_gasreq("offerDetail")) + $$(od_gasbase("offerDetail")));
      // log offer deletion
      delete offers[base][quote][offerId];
      delete offerDetails[base][quote][offerId];
      // credit balanceOf and log transfer
      creditWei(msg.sender, provision);
      emit DexEvents.DeleteOffer(base, quote, offerId);
    } else {
      emit DexEvents.RetractOffer(base, quote, offerId);
    }
  }

  /* ## Update Offer */
  //+clear+
  /* Very similar to `newOffer`, `updateOffer` uses the same code from `DexLib` (`writeOffer`). Makers should use it for updating live offers, but also to save on gas by reusing old, already consumed offers. A pivotId should still be given, to replace the offer at the right book position. It's OK to give the offers' own id as a pivot. */
  function updateOffer(
    address base,
    address quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) public returns (uint) {
    OfferPack memory ofp;
    (ofp.global, ofp.local) = getConfig(base, quote);
    unlockedOnly(ofp.local);
    requireActiveMarket(ofp.global, ofp.local);
    ofp.base = base;
    ofp.quote = quote;
    ofp.wants = wants;
    ofp.gives = gives;
    ofp.id = offerId;
    ofp.gasreq = gasreq;
    ofp.gasprice = gasprice;
    ofp.pivotId = pivotId;
    ofp.oldOffer = offers[base][quote][offerId];
    bytes32 oldLocal = ofp.local;
    writeOffer(ofp, true);
    if (oldLocal != ofp.local) {
      locals[ofp.base][ofp.quote] = ofp.local;
    }
    return ofp.id;
  }

  /* ## Provisioning
  Market makers must have enough provisions for possible penalties. These provisions are in ETH. Every time a new offer is created, the `balanceOf` balance is decreased by the amount necessary to provision the offer's maximum possible penalty. */
  //+clear+

  /* A transfer with enough gas to the Dex will increase the caller's available `balanceOf` balance. _You should send enough gas to execute this function when sending money to the Dex._  */
  function fund(address maker) public payable {
    (bytes32 _global, ) = getConfig(address(0), address(0));
    requireLiveDex(_global);
    creditWei(maker, msg.value);
  }

  receive() external payable {
    fund(msg.sender);
  }

  /* Any provision not currently held to secure an offer's possible penalty is available for withdrawal. */
  function withdraw(uint amount) external returns (bool noRevert) {
    /* Since we only ever send money to the caller, we do not need to provide any particular amount of gas, the caller can manage that themselves. Still, as nonzero value calls provide a 2300 gas stipend, a `withdraw(0)` would trigger a call with actual 0 gas. */
    //if (amount == 0) return;
    //+clear+
    debitWei(msg.sender, amount);
    (noRevert, ) = msg.sender.call{gas: 0, value: amount}("");
  }

  /* # Taker operations */
  //+clear+

  /* ## Market Order */
  //+clear+

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

  /* taker allowances: base => quote => owner => spender => allowance */
  mapping(address => mapping(address => mapping(address => mapping(address => uint))))
    public allowances;
  /* permit nonces */
  mapping(address => uint) public nonces;

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

  //initialized in constructor
  bytes32 public immutable DOMAIN_SEPARATOR;
  // keccak256("Permit(address base,address quote,address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
  bytes32 public constant PERMIT_TYPEHASH =
    0x17a32460f8ed1b6b681cae250706af2a994f0a49f9f87e61c7e4fac936375f5e;

  /* Adapted from Uniswap v2 contract */
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

  function marketOrder(
    address base,
    address quote,
    uint takerWants,
    uint takerGives
  ) external returns (uint, uint) {
    return generalMarketOrder(base, quote, takerWants, takerGives, msg.sender);
  }

  /* The lower-level `marketOrder` can:
   * start walking the OB from best offer
   */
  //+ignore+ ask for a volume by setting takerWants to however much you want and
  //+ignore+ takerGive to max_uint. Any price will be accepted.

  //+ignore+ ask for an average price by setting takerGives such that gives/wants is the price

  //+ignore+ there is no limit price setting

  //+ignore+ setting takerWants to max_int and takergives to however much you're ready to spend will
  //+ignore+ not work, you'll just be asking for a ~0 price.

  /* During execution, we store some values in a memory struct to avoid solc's [stack too deep errors](https://medium.com/coinmonks/stack-too-deep-error-in-solidity-608d1bd6a1ea) that can occur when too many local variables are used. */
  function generalMarketOrder(
    /*   ### Arguments */
    /* A taker calling this function wants to receive `takerWants` `OFR_TOKEN` in return
       for at most `takerGives` `REQ_TOKEN`.
     */
    address base,
    address quote,
    uint takerWants,
    uint takerGives,
    address taker
  ) internal returns (uint, uint) {
    /* ### Checks */
    //+clear+
    /* Since amounts stored in offers are 96 bits wide, checking that `takerWants` fits in 160 bits prevents overflow during the main market order loop. */
    require(uint160(takerWants) == takerWants, "dex/mOrder/takerWants/160bits");

    DC.SingleOrder memory sor;
    sor.base = base;
    sor.quote = quote;
    (sor.global, sor.local) = getConfig(base, quote);
    sor.offerId = $$(loc_best("sor.local"));
    sor.offer = offers[base][quote][sor.offerId];

    MultiOrder memory mor;
    mor.initialWants = takerWants;
    mor.initialGives = takerGives;
    mor.taker = taker;

    /* For the market order to even start, the market needs to be both alive (that is, not irreversibly killed following emergency action), and not currently protected from reentrancy. */
    requireActiveMarket(sor.global, sor.local);
    unlockedOnly(sor.local);

    /* ### Initialization */
    /* The market order will operate as follows : it will go through offers from best to worse, starting from `offerId`, and: */
    /* * will maintain remaining `takerWants` and `takerGives` values. Their initial ratio is the average price the taker will accept. Better prices may be found early in the book, and worse ones later.
     * will not set `prev`/`next` pointers to their correct locations at each offer taken (this is an optimization enabled by forbidding reentrancy).
     * after consuming a segment of offers, will connect the `prev` and `next` neighbors of the segment's ends. */

    /* It is OK to enter the internal market order if the OB is empty, see the stitchOffer call to see why stitchOffer will operate on an offerId == 0 which will reset the OB to empty. */
    sor.local = $$(loc_set("sor.local", [["lock", 1]]));
    locals[base][quote] = sor.local;
    /* first condition means taker wants nothing, and calling internalMarketOrder in that case would execute the first offer for nothig. Second condition means OB is empty and we can't call the offer 0 (its maker is the address 0). */
    internalMarketOrder(mor, sor, mor.initialWants != 0 && sor.offerId != 0);
    sendPenalty(mor.totalPenalty);
    return (mor.totalGot, mor.totalGave);
  }

  /* ### Main loop */
  //+clear+
  /* Offers are looped through until:
   * remaining amount wanted reaches 0, or
   * `offerId == 0`, which means we've gone past the end of the book. */
  function internalMarketOrder(
    MultiOrder memory mor,
    DC.SingleOrder memory sor,
    bool proceed
  ) internal {
    if (proceed) {
      bool success;
      uint gasused;
      bytes32 makerData;
      bytes32 errorCode;
      /* `executed` is false if offer could not be executed against 2nd and 3rd argument of execute. Currently, we interrupt the loop and let the taker leave with less than they asked for (but at a correct price). We could also revert instead of breaking; this could be a configurable flag for the taker to pick. */
      // reduce stack size for recursion

      bool executed;
      sor.wants = mor.initialWants - mor.totalGot;
      sor.gives = mor.initialGives - mor.totalGave;
      sor.offerDetail = offerDetails[sor.base][sor.quote][sor.offerId];

      /* it is crucial that a false success value means that the error is the maker's fault */
      (success, executed, gasused, makerData, errorCode) = execute(mor, sor);

      /* Finally, update `offerId`/`offer` to the next available offer _only if the current offer was deleted_.

         Let _r~1~_, ..., _r~n~_ the successive values taken by `offer` each time the current while loop's test is executed.
         Also, let _r~0~_ = `offers[0]`be the offer immediately better
         than _r~1~_.
         After the market order loop ends, we will restore the doubly linked
         list by connecting _r~0~_ to _r~n~_ through their `prev`/`next`
         pointers. Assume that currently, `offer` is _r~i~_. Should
      we update `offer` to some _r~i+1~_ or is _i_ = _n_?

       * If _r~i~_ was `deleted`, we may or may not be at the last loop iteration, but we will stitch _r~0~_ to some _r~j~_, _j > i_, so we update `offer` to _r~i+1~_ regardless.
        * if _r~i~_ was not `deleted`, we are at the last loop iteration (see why below). So we will stitch _r~0~_ to _r~i~_ = _r~n~_. In that case, we must not update `offer`.

        Note that if the invariant _"not `deleted` → end of `while` loop"_ does not hold, the market order is completely broken.


          Proof that we are at the last iteration of the while loop: if the offer was not deleted, it was not executed. So proceed will be false on the next recursive call. */
      // those may have been updated by execute, we keep them in stack
      {
        /* it is known statically that initialWants-totalGot does not underflow since 1) totalGot is increase by sor.wants during the loop, 2) sor.wants may be clamped down to offer.gives, 3) and sor.wants was at most initialWants-totalGot from earlier step */
        uint stillWants = mor.initialWants - mor.totalGot;
        uint offerId = sor.offerId;
        uint takerWants = sor.wants;
        uint takerGives = sor.gives;
        bytes32 offer = sor.offer;
        bytes32 offerDetail = sor.offerDetail;

        if (executed) {
          // note that internalMarketOrder may be called twice with same offerId, but in that case proceed will be false!
          sor.offerId = $$(o_next("sor.offer"));
          sor.offer = offers[sor.base][sor.quote][sor.offerId];
        }

        /* ! danger ! beyond this point, the following `sor` properties
           reflect the last offer to be examined:
         `offerId`, `offer`, `offerDetail`, `wants`, `gives`, `offerDetail`
       */
        internalMarketOrder(
          mor,
          sor,
          stillWants > 0 && sor.offerId != 0 && executed
        );

        sor.offerId = offerId;
        sor.wants = takerWants;
        sor.gives = takerGives;
        sor.offer = offer;
        sor.offerDetail = offerDetail;
      }

      postExecute(mor, sor, success, executed, gasused, makerData, errorCode);
    } else {
      sor.local = stitchOffers(sor.base, sor.quote, 0, sor.offerId, sor.local);
      sor.local = $$(loc_set("sor.local", [["lock", 0]]));
      locals[sor.base][sor.quote] = sor.local;
      applyFee(mor, sor);
      executeEnd(mor, sor); //noop if classical Dex
    }
  }

  function makerPosthook(
    DC.SingleOrder memory sor,
    uint gasLeft,
    bool success,
    bytes32 makerData,
    bytes32 errorCode
  ) internal returns (uint gasused) {
    // At this point, errorCode can only be "dex/makerRevert" or "dex/makerTransferFail"
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

    bytes memory retdata = new bytes(32);

    address maker = $$(od_maker("sor.offerDetail"));

    uint oldGas = gasleft();
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

  function executeEnd(MultiOrder memory mor, DC.SingleOrder memory sor)
    internal
    virtual;

  function executeCallback(MultiOrder memory mor, DC.SingleOrder memory sor)
    internal
    virtual;

  /* We could make `execute` part of DexLib to reduce Dex contract size, but we make heavy use of the memory struct `sor` to modify data that will then be used by the caller (`internalSnipes` or `internalMarketOrder`). */
  /* maker has failed iff (!success && deleted) */
  /* offer has not been executed iff (!success && !deleted) */
  /* offer has been consumed below dust level if (success && deleted) */
  /* impossible because we always delete offers: (success && !deleted) */
  /* a taker fail triggers a revert */
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
    /* The current offer has a price <code>_p_ = offer.wants/offer.gives</code>. `makerWouldWant` is the amount of `REQ_TOKEN` the offer would require at price _p_ to provide `takerWants` `OFR_TOKEN`. Computing `makeWouldWant` gives us both a test that _p_ is an acceptable price for the taker, and the amount of `REQ_TOKEN` to send to the maker.

    **Note**: We never check that `offerId` is actually a `uint24`, or that `offerId` actually points to an offer: it is not possible to insert an offer with an id larger than that, and a wrong `offerId` will point to a zero-initialized offer, which will revert the call when dividing by `offer.gives`.

   **Note**: Since `takerWants` fits in 160 bits and `offer.wants` fits in 96 bits, the multiplication does not overflow.

   Prices are rounded up. Here is why: offers can be updated. A snipe which names an offer by its id also specifies its price in the form of a `(wants,gives)` pair to be compared to the offers' `(wants,gives)`. See the sniping section for more on why.However, consider an order $r$ for the offer $o$. If $o$ is partially consumed into $o'$ before $r$ is mined, we still want $r$ to succeed (as long as $o'$ has enough volume). But but $o$ wants and give are not $o's$ wants and give. Worse: their ratios are not equal, due to rounding errors.

   Our solution is to make sure that the price of a partially filled offer can only improve. When a snipe can specifies a wants and a gives, it accepts any offer price better than `wants/gives`.

   To do that, we round up the amount required by the maker. That amount will later be deducted from the offer's total volume.
       */
    uint makerWouldWant;

    /* round up ratio */
    {
      uint num = sor.wants * $$(o_wants("sor.offer"));
      uint den = $$(o_gives("sor.offer"));
      makerWouldWant = num / den + (num % den == 0 ? 0 : 1);
    }

    if (makerWouldWant > sor.gives) {
      return (false, false, 0, bytes32(0), bytes32(0));
    }

    executed = true;

    /* If the current offer is good enough for the taker can accept, we compute how much the taker should give/get on the _current offer_. So: `takerWants`,`takerGives` are the residual of how much the taker wants to trade overall, while `sor.wants`,`sor.gives` are how much the taker will trade with the current offer. */
    if ($$(o_gives("sor.offer")) < sor.wants) {
      sor.wants = $$(o_gives("sor.offer"));
      sor.gives = $$(o_wants("sor.offer"));
    } else {
      sor.gives = makerWouldWant;
    }

    /* The flashswap is executed by delegatecall to `FLASHLOANER`. If the call reverts, it means the maker failed to send back `takerWants` `OFR_TOKEN` to the taker. If the call succeeds, `retdata` encodes a boolean indicating whether the taker did send enough to the maker or not.

    Note that any spurious exception due to an error in Dex code will be falsely blamed on the Maker, and its provision for the offer will be unfairly taken away.
    */
    bytes memory retdata;
    (success, retdata) = address(DexLib).delegatecall(
      abi.encodeWithSelector(FLASHLOANER, sor, mor.taker)
    );

    /* Revert if FLASHLOANER reverted. **Danger**: if a well-crafted offer/maker pair can force a revert of FLASHLOANER, the Dex will be stuck. */
    if (success) {
      gasused = abi.decode(retdata, (uint));

      emit DexEvents.Success(
        sor.base,
        sor.quote,
        sor.offerId,
        mor.taker,
        sor.wants,
        sor.gives
      );

      if ($$(glo_notify("sor.global")) > 0) {
        IDexMonitor($$(glo_monitor("sor.global"))).notifySuccess(
          sor,
          mor.taker
        );
      }

      mor.totalGot += sor.wants;
      mor.totalGave += sor.gives;
    } else {
      /* This short reason string should not be exploitable by maker/taker! */
      /* Note that in the tests, the literals are bytes32, while as revert arguments, they are string. */
      (errorCode, gasused, makerData) = innerDecode(retdata);
      if (
        errorCode == "dex/makerRevert" || errorCode == "dex/makerTransferFail"
      ) {
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

        if ($$(glo_notify("sor.global")) > 0) {
          IDexMonitor($$(glo_monitor("sor.global"))).notifyFail(sor, mor.taker);
        }
      } else if (errorCode == "dex/tradeOverflow") {
        revert("dex/tradeOverflow");
      } else if (errorCode == "dex/notEnoughGasForMakerTrade") {
        revert("dex/notEnoughGasForMakerTrade");
      } else if (errorCode == "dex/takerFailToPayMaker") {
        revert("dex/takerFailToPayMaker");
      } else {
        revert("dex/swapError");
      }
    }

    if (executed) {
      dirtyDeleteOffer(sor.base, sor.quote, sor.offerId, sor.offer, !success);
    }
  }

  function innerDecode(bytes memory data)
    internal
    pure
    returns (
      bytes32 errorCode,
      uint gasused,
      bytes32 makerData
    )
  {
    assembly {
      errorCode := mload(add(data, 32))
      gasused := mload(add(data, 64))
      makerData := mload(add(data, 96))
    }
  }

  /* ## Sniping */
  //+clear+
  /* `snipe` takes a single offer from the book, at whatever price is induced by the offer. */

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

  //+clear+
  /*
     From an array of _n_ `(offerId, takerWants,takerGives,gasreq)` pairs (encoded as a `uint[4][]` of size _n_)
     execute each snipe in sequence.
      */
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
    /* ### Pre-loop Checks */
    //+clear+
    DC.SingleOrder memory sor;
    sor.base = base;
    sor.quote = quote;
    (sor.global, sor.local) = getConfig(base, quote);

    MultiOrder memory mor;
    mor.taker = taker;

    requireActiveMarket(sor.global, sor.local);
    unlockedOnly(sor.local);

    /* ### Main loop */
    //+clear+

    sor.local = $$(loc_set("sor.local", [["lock", 1]]));
    locals[base][quote] = sor.local;
    internalSnipes(mor, sor, targets, 0);
    sendPenalty(mor.totalPenalty);
    return (mor.snipeSuccesses, mor.totalGot, mor.totalGave);
  }

  function internalSnipes(
    MultiOrder memory mor,
    DC.SingleOrder memory sor,
    uint[4][] memory targets,
    uint i
  ) internal {
    if (i < targets.length) {
      sor.offerId = targets[i][0];
      sor.offer = offers[sor.base][sor.quote][sor.offerId];
      sor.offerDetail = offerDetails[sor.base][sor.quote][sor.offerId];

      /* If we removed the `isLive` conditional, a single expired or nonexistent offer in `targets` would revert the entire transaction (by the division by `offer.gives` below). We also check that `gasreq` is not worse than specified. A taker who does not care about `gasreq` can specify any amount larger than $2^{24}-1$. */
      if (
        !isLive(sor.offer) || $$(od_gasreq("sor.offerDetail")) > targets[i][3]
      ) {
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

        // ! warning ! updates sor.wants, sor.gives
        (success, executed, gasused, makerData, errorCode) = execute(mor, sor);

        if (success) {
          mor.snipeSuccesses += 1;
        }

        if (executed) {
          sor.local = stitchOffers(
            sor.base,
            sor.quote,
            $$(o_prev("sor.offer")),
            $$(o_next("sor.offer")),
            sor.local
          );
        }

        {
          uint offerId = sor.offerId;
          uint takerWants = sor.wants;
          uint takerGives = sor.gives;
          bytes32 offer = sor.offer;
          bytes32 offerDetail = sor.offerDetail;

          internalSnipes(mor, sor, targets, i + 1);

          sor.offerId = offerId;
          sor.wants = takerWants;
          sor.gives = takerGives;
          sor.offer = offer;
          sor.offerDetail = offerDetail;
        }

        postExecute(mor, sor, success, executed, gasused, makerData, errorCode);
      }
    } else {
      /* `applyFee` extracts the fee from the taker, proportional to the amount purchased */
      sor.local = $$(loc_set("sor.local", [["lock", 0]]));
      locals[sor.base][sor.quote] = sor.local;
      applyFee(mor, sor);
      executeEnd(mor, sor);
    }
  }

  function postExecute(
    MultiOrder memory mor,
    DC.SingleOrder memory sor,
    bool success,
    bool executed,
    uint gasused,
    bytes32 makerData,
    bytes32 errorCode
  ) internal {
    // transfer back to taker in FTD
    if (success) {
      executeCallback(mor, sor);
    }

    // log/notify success/fail, we do it here so config is up to date

    {
      uint gasreq = $$(od_gasreq("sor.offerDetail"));

      if (executed) {
        gasused =
          gasused +
          makerPosthook(
            sor,
            gasused > gasreq ? 0 : gasreq - gasused,
            success,
            makerData,
            errorCode
          );

        if (gasused > gasreq) {
          gasused = gasreq;
        }
      }
    }

    if (!success && executed) {
      mor.totalPenalty += applyPenalty(
        $$(glo_gasprice("sor.global")),
        gasused,
        sor.offer,
        sor.offerDetail
      );
    }
  }

  /* # Low-level offer deletion */
  function dirtyDeleteOffer(
    address base,
    address quote,
    uint offerId,
    bytes32 offer,
    bool deprovision
  ) internal {
    offer = $$(o_set("offer", [["gives", 0]]));
    if (deprovision) {
      offer = $$(o_set("offer", [["gasprice", 0]]));
    }
    offers[base][quote][offerId] = offer;
  }

  /* Post-trade, `applyFee` reaches back into the taker's pocket and extract a fee on the total amount of `OFR_TOKEN` transferred to them. */
  function applyFee(MultiOrder memory mor, DC.SingleOrder memory sor) internal {
    if (mor.totalGot > 0 && $$(loc_fee("sor.local")) > 0) {
      uint concreteFee = (mor.totalGot * $$(loc_fee("sor.local"))) / 10_000;
      mor.totalGot -= concreteFee;
      bool success =
        DexLib.transferToken(sor.base, mor.taker, vault, concreteFee);
      require(success, "dex/takerFailToPayDex");
    }
  }

  /* ## Penalties */
  //+clear+
  /* After any offer executes, `applyPenalty` sends part of the provisioned penalty to the maker, and part to the taker. */
  function applyPenalty(
    uint gasprice,
    uint gasused,
    bytes32 offer,
    bytes32 offerDetail
  ) internal returns (uint) {
    /*
       Then we apply penalties:

     * If the transaction was a success, we entirely refund the maker and send nothing to the taker.

     * Otherwise, the maker loses the cost of `gasused + gasbase` gas. The gas price is estimated by `gasprice`.

     Note that to create the offer, the maker had to provision for `gasreq + gasbase` gas at a price of `offer.gasprice`.

     Note that we do not consider the tx.gasprice.

     Note that `offerDetail.gasbase` and `offer.gasprice` are the values of the Dex parameters `config.gasbase` and `config.gasprice` when the offer was createdd. Without caching, the provision set aside could be insufficient to reimburse the maker (or to compensate the taker).

     */
    uint provision =
      10**9 *
        $$(o_gasprice("offer")) *
        ($$(od_gasreq("offerDetail")) + $$(od_gasbase("offerDetail")));

    /* We take as gasprice min(offer.gasprice,config.gasprice) */
    if ($$(o_gasprice("offer")) < gasprice) {
      gasprice = $$(o_gasprice("offer"));
    }

    /* We set `gasused = min(gasused,gasreq)` since `gasreq < gasused` is possible (e.g. with `gasreq = 0`). */
    if ($$(od_gasreq("offerDetail")) < gasused) {
      gasused = $$(od_gasreq("offerDetail"));
    }

    uint penalty = 10**9 * gasprice * (gasused + $$(od_gasbase("offerDetail")));

    creditWei($$(od_maker("offerDetail")), provision - penalty);

    return penalty;
  }

  function sendPenalty(uint amount) internal {
    if (amount > 0) {
      bool noRevert;
      (noRevert, ) = msg.sender.call{gas: 0, value: amount}("");
    }
  }

  /* # Penalty for failing offers */
  //+clear+

  /* Offers are just promises. They can fail. Penalty provisioning discourages from failing too much: we ask makers to provision more ETH than the expected gas cost of executing their offer and penalize them accoridng to wasted gas.

     Under normal circumstances, we should expect to see bots with a profit expectation dry-running offers locally and executing `snipe` on failing offers, collecting the penalty. The result should be a mostly clean book for actual takers (i.e. a book with only successful offers).

     **Incentive issue**: if the gas price increases enough after an offer has been created, there may not be an immediately profitable way to remove the fake offers. In that case, we count on 3 factors to keep the book clean:
     1. Gas price eventually comes down.
     2. Other market makers want to keep the Dex attractive and maintain their offer flow.
     3. Dex governance (who may collect a fee) wants to keep the Dex attractive and maximize exchange volume.

  /* # Get/set state

  /* ## State
     State getters are available for composing with other contracts & bots. */
  //+clear+

  //+ignore+TODO low gascost bookkeeping methods
  //+ignore+updateOffer(constant price)
  //+ignore+updateOffer(change price)

  /* # Configuration access */
  //+clear+
  /* getter for global and local config. if global.oracle is != 0, global's gasprice and local's density are overriden with the orale value. */
  function getConfig(address base, address quote)
    public
    returns (bytes32 _global, bytes32 _local)
  {
    _global = global;
    _local = locals[base][quote];
    if ($$(glo_useOracle("_global")) > 0) {
      (uint gasprice, uint density) =
        IDexMonitor($$(glo_monitor("_global"))).read(base, quote);
      _global = $$(glo_set("_global", [["gasprice", "gasprice"]]));
      _local = $$(loc_set("_local", [["density", "density"]]));
    }
  }

  /* Setter functions for configuration, called by `setConfig` which also exists in Dex. Overloaded by the type of the `value` parameter. See `DexCommon.sol` for more on the `config` and `key` parameters. */

  /* ## Locals */
  /* ### `active` */
  function activate(
    address base,
    address quote,
    uint fee,
    uint density,
    uint gasbase
  ) public {
    authOnly();
    locals[base][quote] = $$(loc_set("locals[base][quote]", [["active", 1]]));
    setFee(base, quote, fee);
    setDensity(base, quote, density);
    setGasbase(base, quote, gasbase);
    emit DexEvents.SetActive(base, quote, true);
  }

  function deactivate(address base, address quote) public {
    authOnly();
    locals[base][quote] = $$(loc_set("locals[base][quote]", [["active", 0]]));
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
      loc_set("locals[base][quote]", [["fee", "value"]])
    );
    emit DexEvents.SetFee(base, quote, value);
  }

  /* ### `density` */
  /* Useless if global.useOracle is != 0 */
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
      loc_set("locals[base][quote]", [["density", "value"]])
    );
    emit DexEvents.SetDensity(base, quote, value);
  }

  /* ### `gasbase` */
  function setGasbase(
    address base,
    address quote,
    uint value
  ) public {
    authOnly();
    /* Checking the size of `gasbase` is necessary to prevent a) data loss when `gasbase` is copied to an `OfferDetail` struct, and b) overflow when `gasbase` is used in calculations. */
    require(uint24(value) == value, "dex/config/gasbase/24bits");
    //+clear+
    locals[base][quote] = $$(
      loc_set("locals[base][quote]", [["gasbase", "value"]])
    );
    emit DexEvents.SetGasbase(value);
  }

  /* ## Globals */
  /* ### `kill` */
  function kill() public {
    authOnly();
    global = $$(glo_set("global", [["dead", 1]]));
    emit DexEvents.Kill();
  }

  /* ### `gasprice` */
  /* Useless if global.useOracle is != 0 */
  function setGasprice(uint value) public {
    authOnly();
    /* Checking the size of `gasprice` is necessary to prevent a) data loss when `gasprice` is copied to an `OfferDetail` struct, and b) overflow when `gasprice` is used in calculations. */
    require(uint16(value) == value, "dex/config/gasprice/16bits");
    //+clear+

    global = $$(glo_set("global", [["gasprice", "value"]]));
    emit DexEvents.SetGasprice(value);
  }

  /* ### `gasmax` */
  function setGasmax(uint value) public {
    authOnly();
    /* Since any new `gasreq` is bounded above by `config.gasmax`, this check implies that all offers' `gasreq` is 24 bits wide at most. */
    require(uint24(value) == value, "dex/config/gasmax/24bits");
    //+clear+
    global = $$(glo_set("global", [["gasmax", "value"]]));
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
    global = $$(glo_set("global", [["monitor", "value"]]));
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
      global = $$(glo_set("global", [["useOracle", 1]]));
    } else {
      global = $$(glo_set("global", [["useOracle", 0]]));
    }
    emit DexEvents.SetUseOracle(value);
  }

  function setNotify(bool value) public {
    authOnly();
    if (value) {
      global = $$(glo_set("global", [["notify", 1]]));
    } else {
      global = $$(glo_set("global", [["notify", 0]]));
    }
    emit DexEvents.SetNotify(value);
  }

  function writeOffer(OfferPack memory ofp, bool update) internal {
    /* We check gasprice,gives,wants,gasreq size to avoid checking a high gasprice, then reducing it by packing. */
    require(
      uint16(ofp.gasprice) == ofp.gasprice,
      "dex/writeOffer/gasprice/16bits"
    );
    require(uint96(ofp.wants) == ofp.wants, "dex/writeOffer/wants/96bits");
    require(uint96(ofp.gives) == ofp.gives, "dex/writeOffer/gives/96bits");
    require(uint24(ofp.gasreq) == ofp.gasreq, "dex/writeOffer/gasreq/24bits");

    /* gasprice given by maker will be bounded below by internal gasprice estimate at offer write time. with a large enough overapproximation of the gasprice, the maker can regularly update their offer without updating it.  */
    if (ofp.gasprice < $$(glo_gasprice("ofp.global"))) {
      ofp.gasprice = $$(glo_gasprice("ofp.global"));
    }

    {
      bytes32 writeOfferData =
        $$(
          wo_make(
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

    /* The following checks are first performed: */
    //+clear+
    /* * Check `gasreq` below limit. Implies `gasreq` at most 24 bits wide, which ensures no overflow in computation of `provision` (see below). */
    require(
      ofp.gasreq <= $$(glo_gasmax("ofp.global")),
      "dex/writeOffer/gasreq/tooHigh"
    );
    /* * Make sure `give > 0` -- division by 0 would throw in several places otherwise, and `isLive` relies on it. */
    require(ofp.gives > 0, "dex/writeOffer/gives/tooLow");
    /* * Make sure that the maker is posting a 'dense enough' offer: the ratio of `OFR_TOKEN` offered per gas consumed must be high enough. The actual gas cost paid by the taker is overapproximated by adding `gasbase` to `gasreq`. */
    require(
      ofp.gives >=
        (ofp.gasreq + $$(loc_gasbase("ofp.local"))) *
          $$(loc_density("ofp.local")),
      "dex/writeOffer/density/tooLow"
    );

    /* First, we write the new offerDetails and remember the previous provision (0 by default, for new offers) to balance out maker's `balanceOf`. */
    uint oldProvision;
    {
      bytes32 offerDetail = offerDetails[ofp.base][ofp.quote][ofp.id];
      if (update) {
        require(
          msg.sender == $$(od_maker("offerDetail")),
          "dex/updateOffer/unauthorized"
        );
        oldProvision =
          10**9 *
          $$(o_gasprice("ofp.oldOffer")) *
          ($$(od_gasreq("offerDetail")) + $$(od_gasbase("offerDetail")));
      }

      //TODO check that we're using less gas if those values haven't changed
      if (
        /* It is currently not possible for a new offer to fail the 3 last tests, but it may in the future, so we make sure we're semantically correct by checking for `!update`. */
        !update ||
        $$(od_gasreq("offerDetail")) != ofp.gasreq ||
        $$(od_gasbase("offerDetail")) != $$(loc_gasbase("ofp.local"))
      ) {
        uint gasbase = $$(loc_gasbase("ofp.local"));
        offerDetails[ofp.base][ofp.quote][ofp.id] = $$(
          od_make(
            [
              ["maker", "uint(msg.sender)"],
              ["gasreq", "ofp.gasreq"],
              ["gasbase", "gasbase"]
            ]
          )
        );
      }
    }

    /* With every change to an offer, a maker must deduct provisions from its `balanceOf` balance, or get some back if the updated offer requires fewer provisions. */

    {
      uint provision =
        (ofp.gasreq + $$(loc_gasbase("ofp.local"))) * ofp.gasprice * 10**9;
      if (provision > oldProvision) {
        debitWei(msg.sender, provision - oldProvision);
      } else if (provision < oldProvision) {
        creditWei(msg.sender, oldProvision - provision);
      }
    }

    /* The position of the new or updated offer is found using `findPosition`. If the offer is the best one, `prev == 0`, and if it's the last in the book, `next == 0`.

       `findPosition` is only ever called here, but exists as a separate function to make the code easier to read. */
    (uint prev, uint next) = findPosition(ofp);
    /* Then we place the offer in the book at the position found by `findPosition`.

       If the offer is not the best one, we update its predecessor; otherwise we update the `best` value. */

    /* tests if offer has moved in the book (or was not already there) if next == ofp.id, then the new offer parameters are strictly better than before but still worse than the old prev. if prev == ofp.id, then the new offer parameters are worse or as good as before but still better than the old next. */
    if (!(next == ofp.id || prev == ofp.id)) {
      if (prev != 0) {
        offers[ofp.base][ofp.quote][prev] = $$(
          o_set("offers[ofp.base][ofp.quote][prev]", [["next", "ofp.id"]])
        );
      } else {
        ofp.local = $$(loc_set("ofp.local", [["best", "ofp.id"]]));
      }

      /* If the offer is not the last one, we update its successor. */
      if (next != 0) {
        offers[ofp.base][ofp.quote][next] = $$(
          o_set("offers[ofp.base][ofp.quote][next]", [["prev", "ofp.id"]])
        );
      }

      /* An important invariant is that an offer is 'live' iff (gives > 0) iff (the offer is in the book). Here, we are about to *move* the offer, so we start by taking it out of the book. Note that unconditionally calling `stitchOffers` would break the book since it would connect offers that may have moved. A priori, if `writeOffer` is called by `newOffer`, `oldOffer` should be all zeros and thus not live. But that would be assuming a subtle implementation detail of `isLive`, so we add the (currently redundant) check on `update`).
       */
      if (update && isLive(ofp.oldOffer)) {
        ofp.local = stitchOffers(
          ofp.base,
          ofp.quote,
          $$(o_prev("ofp.oldOffer")),
          $$(o_next("ofp.oldOffer")),
          ofp.local
        );
      }
    }

    /* With the `prev`/`next` in hand, we store the offer in the `offers` and `offerDetails` maps. Note that by `Dex`'s `newOffer` function, `offerId` will always fit in 24 bits (if there is an update, `offerDetails[offerId]` must be owned by `msg.sender`, os `offerId` has the right width). */
    bytes32 ofr =
      $$(
        o_make(
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

  /* `findPosition` takes a price in the form of a `wants/gives` pair, an offer id (`pivotId`) and walks the book from that offer (backward or forward) until the right position for the price `wants/gives` is found. The position is returned as a `(prev,next)` pair, with `prev` or `next` at 0 to mark the beginning/end of the book (no offer ever has id 0).

  If prices are equal, `findPosition` will put the newest offer last. */
  function findPosition(
    /* This part of the code relies on consumed offers being deleted, otherwise we would blindly insert offers next to garbage old values. */
    OfferPack memory ofp
  ) internal view returns (uint, uint) {
    uint pivotId = ofp.pivotId;
    /* optimize for the case wher pivot info is already known */
    bytes32 pivot =
      pivotId == ofp.id ? ofp.oldOffer : offers[ofp.base][ofp.quote][pivotId];

    if (!isLive(pivot)) {
      // in case pivotId is not or no longer a valid offer
      pivotId = $$(loc_best("ofp.local"));
      pivot = offers[ofp.base][ofp.quote][pivotId];
    }

    // pivot better than `wants/gives`, we follow next
    if (better(ofp, pivot, pivotId)) {
      bytes32 pivotNext;
      while ($$(o_next("pivot")) != 0) {
        uint pivotNextId = $$(o_next("pivot"));
        pivotNext = offers[ofp.base][ofp.quote][pivotNextId];
        if (better(ofp, pivotNext, pivotNextId)) {
          pivotId = pivotNextId;
          pivot = pivotNext;
        } else {
          break;
        }
      }
      // this is also where we end up with an empty book
      return (pivotId, $$(o_next("pivot")));

      // pivot strictly worse than `wants/gives`, we follow prev
    } else {
      bytes32 pivotPrev;
      while ($$(o_prev("pivot")) != 0) {
        uint pivotPrevId = $$(o_prev("pivot"));
        pivotPrev = offers[ofp.base][ofp.quote][pivotPrevId];
        if (better(ofp, pivotPrev, pivotPrevId)) {
          break;
        } else {
          pivotId = pivotPrevId;
          pivot = pivotPrev;
        }
      }
      return ($$(o_prev("pivot")), pivotId);
    }
  }

  /* The utility method `better`
    returns false iff the point induced by _(`wants1`,`gives1`,`offerDetails[offerId1].gasreq`)_ is strictly worse than the point induced by _(`wants2`,`gives2`,`gasreq2`)_. It makes `findPosition` easier to read. "Worse" is defined on the lexicographic order $\textrm{price} \times_{\textrm{lex}} \textrm{density}^{-1}$.

    This means that for the same price, offers that deliver more volume per gas are taken first.

    To save gas, instead of giving the `gasreq1` argument directly, we provide a path to it (with `offerDetails` and `offerid1`). If necessary (ie. if the prices `wants1/gives1` and `wants2/gives2` are the same), we spend gas and read `gasreq2`.

  */
  function better(
    OfferPack memory ofp,
    bytes32 offer1,
    //uint wants1,
    //uint gives1,
    uint offerId1
  ) internal view returns (bool) {
    uint wants1 = $$(o_wants("offer1"));
    uint gives1 = $$(o_gives("offer1"));
    if (offerId1 == 0) {
      return false;
    } //happens on empty OB
    uint wants2 = ofp.wants;
    uint gives2 = ofp.gives;
    uint weight1 = wants1 * gives2;
    uint weight2 = wants2 * gives1;
    if (weight1 == weight2) {
      uint gasreq1 =
        $$(od_gasreq("offerDetails[ofp.base][ofp.quote][offerId1]"));
      uint gasreq2 = ofp.gasreq;
      return (gives1 * gasreq2 >= gives2 * gasreq1); //density1 is higher
    } else {
      return weight1 < weight2; //price1 is lower
    }
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

  /* The Dex holds a `uint => Offer` mapping in storage. Offer ids that are not yet assigned or that point to since-deleted offer will point to an uninitialized struct. A common way to check for initialization is to add an `exists` field to the struct. In our case, an invariant of the Dex is: on an existing offer, `offer.gives > 0`. So we just check the `gives` field. */
  /* An important invariant is that an offer is 'live' iff (gives > 0) iff (the offer is in the book). */
  function isLive(bytes32 offer) public pure returns (bool) {
    return $$(o_gives("offer")) > 0;
  }

  /* Connect the predecessor and sucessor of `id` through their `next`/`prev` pointers. For more on the book structure, see `DexCommon.sol`. This step is not necessary during a market order, so we only call `dirtyDeleteOffer` */
  /* !warning! calling with pastId=0 will set futureId as the best. So with pastId=0, futureId=0, it sets the OB to empty and loses track of existing offers. */
  /* !warning! may make memory copy of local.best stale. returns new local. */
  function stitchOffers(
    address base,
    address quote,
    uint pastId,
    uint futureId,
    bytes32 local
  ) internal returns (bytes32) {
    if (pastId != 0) {
      offers[base][quote][pastId] = $$(
        o_set("offers[base][quote][pastId]", [["next", "futureId"]])
      );
    } else {
      local = $$(loc_set("local", [["best", "futureId"]]));
    }

    if (futureId != 0) {
      offers[base][quote][futureId] = $$(
        o_set("offers[base][quote][futureId]", [["prev", "pastId"]])
      );
    }

    return local;
  }
}

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

  /* we use `transferFrom` with takers (instead of `balanceOf` technique) for the following reason :
     * we want the taker to be awaken after all loans have been made
     * 1) so either the taker gets a list of all makers and loops through them to pay back, or
     * 2) we call a new taker method "payback" after returning from each maker call, or
     * 3) we call transferFrom after returning from each maker call
     So :
     1) would mean accumulating a list of all makers, which would make the market order code too complex
     2) is OK, but has an extra CALL cost on top of the token transfer, one for each maker. This is unavoidable anyway when calling makerTrade (since the maker must be able to execute arbitrary code at that moment), but we can skip it here.
     3) is the cheapest, but it has the drawbacks of `transferFrom`: money must end up owned by the taker, and taker needs to `approve` Dex
   */
  function executeCallback(MultiOrder memory mor, DC.SingleOrder memory sor)
    internal
    override
  {
    bool success =
      DexLib.transferToken(
        sor.quote,
        mor.taker,
        $$(od_maker("sor.offerDetail")),
        $$(o_gives("sor.offer"))
      );
    require(success, "dex/takerFailToPayMaker");
  }
}
