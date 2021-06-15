// SPDX-License-Identifier: MIT-license
pragma solidity ^0.7.0;
pragma abicoder v2;

contract MgvCommon {
    struct SingleOrder { 
    address base;
    address quote;
    uint256 offerId;
    bytes32 offer;
    uint256 wants;
    uint256 gives;
    bytes32 offerDetail;
    bytes32 global;
    bytes32 local;
    }

    struct Global { 
    address monitor;
    bool useOracle;
    bool notify;
    uint256 gasprice;
    uint256 gasmax;
    bool dead; 
    }

    struct Local { 
    bool active;
    uint256 fee;
    uint256 density;
    uint256 overhead_gasbase;
    uint256 offer_gasbase;
    bool lock;
    uint256 best;
    uint256 last; 
    }

    struct Config {
    Global global;
    Local local; 
    }

    struct Offer {
    uint256 prev;
    uint256 next;
    uint256 gives;
    uint256 wants;
    uint256 gasprice; 
    }

    struct OfferDetail { 
    address maker;
    uint256 gasreq;
    uint256 overhead_gasbase;
    uint256 offer_gasbase; 
    }
   
    struct OrderResult {
    bool success;
    bytes32 makerData;
    bytes32 errorCode;
  }
}

interface IMangrove {
    function DOMAIN_SEPARATOR(  ) external view returns (bytes32 ) ;
    function PERMIT_TYPEHASH(  ) external view returns (bytes32 ) ;
    function activate( address base,address quote,uint256 fee,uint256 density,uint256 overhead_gasbase,uint256 offer_gasbase ) external   ;
    function allowances( address ,address ,address ,address  ) external view returns (uint256 ) ;
    function approve( address base,address quote,address spender,uint256 value ) external  returns (bool ) ;
    function balanceOf( address  ) external view returns (uint256 ) ;
    function best( address base,address quote ) external view returns (uint256 ) ;
    function config( address base,address quote ) external  returns (bytes32 _global, bytes32 _local) ;
    function deactivate( address base,address quote ) external   ;
    function flashloan( MgvCommon.SingleOrder memory sor,address taker ) external  returns (uint256 gasused) ;
    function fund( address maker ) external payable  ;
    function getConfig( address base,address quote ) external  returns (MgvCommon.Config memory ret) ;
    function global(  ) external view returns (bytes32 ) ;
    function governance(  ) external view returns (address ) ;
    function invertedFlashloan( MgvCommon.SingleOrder memory sor,address  ) external  returns (uint256 gasused) ;
    function isLive( bytes32 offer ) external pure returns (bool ) ;
    function kill(  ) external   ;
    function locals( address ,address  ) external view returns (bytes32 ) ;
    function locked( address base,address quote ) external view returns (bool ) ;
    function marketOrder( address base,address quote,uint256 takerWants,uint256 takerGives ) external  returns (uint256 , uint256 ) ;
    function marketOrderFor( address base,address quote,uint256 takerWants,uint256 takerGives,address taker ) external  returns (uint256 takerGot, uint256 takerGave) ;
    function newOffer( address base,address quote,uint256 wants,uint256 gives,uint256 gasreq,uint256 gasprice,uint256 pivotId ) external  returns (uint256 ) ;
    function nonces( address  ) external view returns (uint256 ) ;
    function offerDetails( address ,address ,uint256  ) external view returns (bytes32 ) ;
    function offerInfo( address base,address quote,uint256 offerId ) external view returns (MgvCommon.Offer memory , MgvCommon.OfferDetail memory ) ;
    function offers( address ,address ,uint256  ) external view returns (bytes32 ) ;
    function permit( address base,address quote,address owner,address spender,uint256 value,uint256 deadline,uint8 v,bytes32 r,bytes32 s ) external   ;
    function retractOffer( address base,address quote,uint256 offerId,bool _deprovision ) external   ;
    function setDensity( address base,address quote,uint256 density ) external   ;
    function setFee( address base,address quote,uint256 fee ) external   ;
    function setGasbase( address base,address quote,uint256 overhead_gasbase,uint256 offer_gasbase ) external   ;
    function setGasmax( uint256 gasmax ) external   ;
    function setGasprice( uint256 gasprice ) external   ;
    function setGovernance( address governanceAddress ) external   ;
    function setMonitor( address monitor ) external   ;
    function setNotify( bool notify ) external   ;
    function setUseOracle( bool useOracle ) external   ;
    function setVault( address vaultAddress ) external   ;
    function snipe( address base,address quote,uint256 offerId,uint256 takerWants,uint256 takerGives,uint256 gasreq ) external  returns (bool , uint256 , uint256 ) ;
    function snipeFor( address base,address quote,uint256 offerId,uint256 takerWants,uint256 takerGives,uint256 gasreq,address taker ) external  returns (bool success, uint256 takerGot, uint256 takerGave) ;
    function snipes( address base,address quote,uint256[4][] memory targets ) external  returns (uint256 , uint256 , uint256 ) ;
    function snipesFor( address base,address quote,uint256[4][] memory targets,address taker ) external  returns (uint256 successes, uint256 takerGot, uint256 takerGave) ;
    function updateOffer( address base,address quote,uint256 wants,uint256 gives,uint256 gasreq,uint256 gasprice,uint256 pivotId,uint256 offerId ) external  returns (uint256 ) ;
    function vault(  ) external view returns (address ) ;
    function withdraw( uint256 amount ) external  returns (bool noRevert) ;
    receive () external payable;
}

/* # IMaker interface */
interface IMaker {
  /* Called upon offer execution. If this function reverts, Mangrove will not try to transfer funds. Returned data (truncated to 32 bytes) can be accessed during the call to `makerPosthook` in the `result.errorCode` field.
  Reverting with a message (for further processing during posthook) should be done using low level `revertTrade(bytes32)` provided in the `MgvIt` library. It is not possible to reenter the order book of the traded pair whilst this function is executed.*/
  function makerTrade(MgvCommon.SingleOrder calldata order)
    external
    returns (bytes32);

  /* Called after all offers of an order have been executed. Posthook of the last executed order is called first and full reentrancy into the Mangrove is enabled at this time. `order` recalls key arguments of the order that was processed and `result` recalls important information for updating the current offer.*/
  function makerPosthook(
    MgvCommon.SingleOrder calldata order,
    MgvCommon.OrderResult calldata result
  ) external;
}

/* # ITaker interface */
interface ITaker {
  /* FTD only: call to taker after loans went through */
  function takerTrade(
    address base,
    address quote,
    // total amount of base token that was flashloaned to the taker
    uint totalGot,
    // total amount of quote token that should be made available
    uint totalGives
  ) external;
}
