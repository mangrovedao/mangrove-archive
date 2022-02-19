// SPDX-License-Identifier: Unlicense

// MgvLib.sol

// This is free and unencumbered software released into the public domain.

// Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.

// In jurisdictions that recognize copyright laws, the author or authors of this software dedicate any and all copyright interest in the software to the public domain. We make this dedication for the benefit of the public at large and to the detriment of our heirs and successors. We intend this dedication to be an overt act of relinquishment in perpetuity of all present and future rights to this software under copyright law.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// For more information, please refer to <https://unlicense.org/>

/* `MgvLib` contains data structures returned by external calls to Mangrove and the interfaces it uses for its own external calls. */

pragma solidity ^0.7.0;
pragma abicoder v2;

import "./IERC20.sol";

/* # Structs
The structs defined in `structs.js` have their counterpart as solidity structs that are easy to manipulate for outside contracts / callers of view functions. */
library MgvLib {
  struct Offer {
    uint prev;
    uint next;
    uint gives;
    uint wants;
    uint gasprice;
  }

  struct OfferDetail {
    address maker;
    uint gasreq;
    uint overhead_gasbase;
    uint offer_gasbase;
  }
  struct Global {
    address monitor;
    bool useOracle;
    bool notify;
    uint gasprice;
    uint gasmax;
    bool dead;
  }

  struct Local {
    bool active;
    uint fee;
    uint density;
    uint overhead_gasbase;
    uint offer_gasbase;
    bool lock;
    uint best;
    uint last;
  }

  struct Config {
    Global global;
    Local local;
  }

  /*
   Some miscellaneous data types useful to `Mangrove` and external contracts */
  //+clear+

  /* `SingleOrder` holds data about an order-offer match in a struct. Used by `marketOrder` and `internalSnipes` (and some of their nested functions) to avoid stack too deep errors. */
  struct SingleOrder {
    address base;
    address quote;
    uint offerId;
    bytes32 offer;
    /* `wants`/`gives` mutate over execution. Initially the `wants`/`gives` from the taker's pov, then actual `wants`/`gives` adjusted by offer's price and volume. */
    uint wants;
    uint gives;
    /* `offerDetail` is only populated when necessary. */
    bytes32 offerDetail;
    bytes32 global;
    bytes32 local;
  }

  /* <a id="MgvLib/OrderResult"></a> `OrderResult` holds additional data for the maker and is given to them _after_ they fulfilled an offer. It gives them their own returned data from the previous call, and an `statusCode` specifying whether the Mangrove encountered an error. */

  struct OrderResult {
    /* `makerdata` holds a message that was either returned by the maker or passed as revert message at the end of the trade execution*/
    bytes32 makerData;
    /* `statusCode` is an [internal Mangrove status](#MgvOfferTaking/statusCodes) code. */
    bytes32 statusCode;
  }
}

/* # Events
The events emitted for use by bots are listed here: */
library MgvEvents {
  /* * Emitted at the creation of the new Mangrove contract on the pair (`quote`, `base`)*/
  event NewMgv();

  /* Mangrove adds or removes wei from `maker`'s account */
  /* * Credit event occurs when an offer is removed from the Mangrove or when the `fund` function is called*/
  event Credit(address indexed maker, uint amount);
  /* * Debit event occurs when an offer is posted or when the `withdraw` function is called */
  event Debit(address indexed maker, uint amount);

  /* * Mangrove reconfiguration */
  event SetActive(address indexed base, address indexed quote, bool value);
  event SetFee(address indexed base, address indexed quote, uint value);
  event SetGasbase(
    address indexed base,
    address indexed quote,
    uint overhead_gasbase,
    uint offer_gasbase
  );
  event SetGovernance(address value);
  event SetMonitor(address value);
  event SetVault(address value);
  event SetUseOracle(bool value);
  event SetNotify(bool value);
  event SetGasmax(uint value);
  event SetDensity(address indexed base, address indexed quote, uint value);
  event SetGasprice(uint value);

  /* * Offer execution */
  event Success(
    address indexed base,
    address indexed quote,
    uint offerId,
    // maker's address is not logged because it can be retrieved from `WriteOffer` event using `offerId`.
    address taker,
    uint takerWants,
    uint takerGives
  );

  /* Log information when a trade execution reverts */
  event MakerFail(
    address indexed base,
    address indexed quote,
    uint offerId,
    // maker's address is not logged because it can be retrieved from `WriteOffer` event using `offerId`.
    address taker,
    uint takerWants,
    uint takerGives,
    // `statusCode` may only be `"mgv/makerRevert"`, `"mgv/makerTransferFail"` or `"mgv/makerReceiveFail"`
    bytes32 statusCode,
    bytes32 makerData
  );

  /* Log information when a posthook reverts */
  event PosthookFail(
    address indexed base,
    address indexed quote,
    uint offerId,
    bytes32 makerData
  );

  /* * After `permit` and `approve` */
  event Approval(
    address indexed base,
    address indexed quote,
    address owner,
    address spender,
    uint value
  );

  /* * Mangrove closure */
  event Kill();

  /* * An offer was created or updated. */
  event WriteOffer(
    address indexed base,
    address indexed quote,
    address maker,
    uint makerWants,
    uint makerGives,
    uint gasprice,
    uint gasreq,
    uint offerId
  );

  /* * `offerId` was present and is now removed from the book. */
  event RetractOffer(address indexed base, address indexed quote, uint offerId);
}

/* # IMaker interface */
interface IMaker {
  /* Called upon offer execution. If this function reverts, Mangrove will not try to transfer funds. Returned data (truncated to leftmost 32 bytes) can be accessed during the call to `makerPosthook` in the `result.statusCode` field. To revert with a 32 bytes value, use something like:
     ```
     function tradeRevert(bytes32 data) internal pure {
       bytes memory revData = new bytes(32);
         assembly {
           mstore(add(revData, 32), data)
           revert(add(revData, 32), 32)
         }
     }
     ```
     */
  function makerExecute(MgvLib.SingleOrder calldata order)
    external
    returns (bytes32);

  /* Called after all offers of an order have been executed. Posthook of the last executed order is called first and full reentrancy into the Mangrove is enabled at this time. `order` recalls key arguments of the order that was processed and `result` recalls important information for updating the current offer. (see [above](#MgvLib/OrderResult))*/
  function makerPosthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) external;
}

/* # ITaker interface */
interface ITaker {
  /* Inverted mangrove only: call to taker after loans went through */
  function takerTrade(
    address base,
    address quote,
    // total amount of base token that was flashloaned to the taker
    uint totalGot,
    // total amount of quote token that should be made available
    uint totalGives
  ) external;
}

/* # Monitor interface
If enabled, the monitor receives notification after each offer execution and is read for each pair's `gasprice` and `density`. */
interface IMgvMonitor {
  function notifySuccess(MgvLib.SingleOrder calldata sor, address taker)
    external;

  function notifyFail(MgvLib.SingleOrder calldata sor, address taker) external;

  function read(address base, address quote)
    external
    view
    returns (uint gasprice, uint density);
}
