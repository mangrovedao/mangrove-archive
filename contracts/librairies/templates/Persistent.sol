pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";

abstract contract Persistent is MangroveOffer {

  constructor() {}

  // function should be called during a posthook execution
  function __posthook_repostUpdatedOffer(
    MgvC.SingleOrder calldata order,
    uint _wants,
    uint _gives,
    uint _gasreq,
    uint _gasprice
  ) internal {
    uint None = uint(-1);
    // update offer with new price (with mangroveOffer_env.gives) and pivotId 0
    (uint wants, uint gives, uint gasreq, uint gasprice) = __trade_posthook_getStoredOffer(order);
    wants = (_wants == None) ? wants : _wants;
    gives = (_gives == None) ? gives : _gives;
    gasreq = (_gasreq == None) ? gasreq : _gasreq;
    gasprice = (_gasprice == None) ? gasprice : _gasprice;
    updateMangroveOffer(order.quote, wants, gives, gasreq, gasprice, 0, order.offerId);
  }

  function __posthook_repostOfferAsIs(
    MgvC.SingleOrder calldata order
    ) internal {
    (uint wants, uint gives, uint gasreq, uint gasprice) = __trade_posthook_getStoredOffer(order);
    updateMangroveOffer(order.quote, wants, gives, gasreq, gasprice, 0, order.offerId);
  }

}
