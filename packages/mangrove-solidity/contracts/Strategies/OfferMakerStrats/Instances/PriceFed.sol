pragma solidity ^0.7.0;
pragma abicoder v2;

import "../Defensive.sol";

contract PriceFed is Defensive {
  constructor(
    address _oracle,
    address payable _MGV
  ) Defensive(_oracle, _MGV){}

  // reposts only if offer was reneged due to a price slippage
  function __postHookPriceUpdate__(
    uint oracle_wants, 
    uint oracle_gives, 
    MgvLib.SingleOrder calldata order
    ) internal override {
      (uint old_wants, uint old_gives,,) = unpackOfferFromOrder(order);
      // one wants to find Delta_wants such that:
      // (old_wants+Delta)/old_gives = oracle_wants/oracle_gives
      // i.e Delta = oracle_wants [96] * old_gives [96] / oracle_gives  [96] - old_wants [96]
      uint delta = sub_(
        div_(
          mul_(oracle_wants, old_gives),
          oracle_gives
        ),
        mul_(old_wants, oracle_gives)
      );
      // since offer is persistent it will auto refill if contract does not have enough provision on the Mangrove
      updateOffer(
        order.base, 
        order.quote, 
        add_(old_wants,delta), 
        old_gives, MAXUINT, MAXUINT, MAXUINT, 
        order.offerId
      );
  }
  function __autoRefill__(uint amount) internal override {
    require (address(this).balance >= amount, "Insufficient fund to provision offer");
    MGV.fund{value:amount}();
  }
  
}
