// SPDX-License-Identifier: MIT-license
pragma solidity ^0.7.0;
pragma abicoder v2;

contract MgvLib {
  struct SingleOrder {
    address base;
    address quote;
    uint offerId;
    bytes32 offer;
    uint wants;
    uint gives;
    bytes32 offerDetail;
    bytes32 global;
    bytes32 local;
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

  struct OrderResult {
    bytes32 makerData;
    bytes32 statusCode;
  }
}

interface IMangrove {
  function DOMAIN_SEPARATOR() external view returns (bytes32);

  function PERMIT_TYPEHASH() external view returns (bytes32);

  function activate(
    address base,
    address quote,
    uint fee,
    uint density,
    uint overhead_gasbase,
    uint offer_gasbase
  ) external;

  function allowances(
    address,
    address,
    address,
    address
  ) external view returns (uint);

  function approve(
    address base,
    address quote,
    address spender,
    uint value
  ) external returns (bool);

  function balanceOf(address) external view returns (uint);

  function best(address base, address quote) external view returns (uint);

  function config(address base, address quote)
    external
    returns (bytes32 _global, bytes32 _local);

  function deactivate(address base, address quote) external;

  function flashloan(MgvLib.SingleOrder memory sor, address taker)
    external
    returns (uint gasused);

  function fund(address maker) external payable;

  function getConfig(address base, address quote)
    external
    returns (MgvLib.Config memory ret);

  function global() external view returns (bytes32);

  function governance() external view returns (address);

  function invertedFlashloan(MgvLib.SingleOrder memory sor, address)
    external
    returns (uint gasused);

  function isLive(bytes32 offer) external pure returns (bool);

  function kill() external;

  function locals(address, address) external view returns (bytes32);

  function locked(address base, address quote) external view returns (bool);

  function marketOrder(
    address base,
    address quote,
    uint takerWants,
    uint takerGives,
    bool fillWants
  ) external returns (uint, uint);

  function marketOrderFor(
    address base,
    address quote,
    uint takerWants,
    uint takerGives,
    bool fillWants,
    address taker
  ) external returns (uint takerGot, uint takerGave);

  function newOffer(
    address base,
    address quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) external returns (uint);

  function nonces(address) external view returns (uint);

  function offerDetails(
    address,
    address,
    uint
  ) external view returns (bytes32);

  function offerInfo(
    address base,
    address quote,
    uint offerId
  ) external view returns (MgvLib.Offer memory, MgvLib.OfferDetail memory);

  function offers(
    address,
    address,
    uint
  ) external view returns (bytes32);

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
  ) external;

  function retractOffer(
    address base,
    address quote,
    uint offerId,
    bool _deprovision
  ) external;

  function setDensity(
    address base,
    address quote,
    uint density
  ) external;

  function setFee(
    address base,
    address quote,
    uint fee
  ) external;

  function setGasbase(
    address base,
    address quote,
    uint overhead_gasbase,
    uint offer_gasbase
  ) external;

  function setGasmax(uint gasmax) external;

  function setGasprice(uint gasprice) external;

  function setGovernance(address governanceAddress) external;

  function setMonitor(address monitor) external;

  function setNotify(bool notify) external;

  function setUseOracle(bool useOracle) external;

  function setVault(address vaultAddress) external;

  function snipe(
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint gasreq,
    bool fillWants
  )
    external
    returns (
      bool,
      uint,
      uint
    );

  function snipeFor(
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint gasreq,
    bool fillWants,
    address taker
  )
    external
    returns (
      bool success,
      uint takerGot,
      uint takerGave
    );

  function snipes(
    address base,
    address quote,
    uint[4][] memory targets,
    bool fillWants
  )
    external
    returns (
      uint,
      uint,
      uint
    );

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
    );

  function updateOffer(
    address base,
    address quote,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) external returns (uint);

  function vault() external view returns (address);

  function withdraw(uint amount) external returns (bool noRevert);

  receive() external payable;
}

/* # IMaker interface */
interface IMaker {
  /* Called upon offer execution. If this function reverts, Mangrove will not try to transfer funds. Returned data (truncated to 32 bytes) can be accessed during the call to `makerPosthook` in the `result.errorCode` field.
  Reverting with a message (for further processing during posthook) should be done using low level `revertTrade(bytes32)` provided in the `MgvIt` library. It is not possible to reenter the order book of the traded pair whilst this function is executed.*/
  function makerExecute(MgvLib.SingleOrder calldata order)
    external
    returns (bytes32);

  /* Called after all offers of an order have been executed. Posthook of the last executed order is called first and full reentrancy into the Mangrove is enabled at this time. `order` recalls key arguments of the order that was processed and `result` recalls important information for updating the current offer.*/
  function makerPosthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) external;
}

/* # ITaker interface */
interface ITaker {
  /* Inverted Mangrove only: call to taker after loans went through */
  function takerTrade(
    address base,
    address quote,
    // total amount of base token that was flashloaned to the taker
    uint totalGot,
    // total amount of quote token that should be made available
    uint totalGives
  ) external;
}
