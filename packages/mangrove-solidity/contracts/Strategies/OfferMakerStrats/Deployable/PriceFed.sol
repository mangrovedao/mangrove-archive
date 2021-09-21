pragma solidity ^0.7.0;
pragma abicoder v2;

import "../Defensive.sol";
import "../AaveLender.sol";

import "hardhat/console.sol";

contract PriceFed is Defensive, AaveLender {
  constructor(
    address _oracle,
    address _addressesProvider,
    address payable _MGV
  ) Defensive(_oracle) AaveLender(_addressesProvider, 0) MangroveOffer(_MGV) {}

  // reposts only if offer was reneged due to a price slippage
  function __postHookPriceUpdate__(
    bytes32 message,
    MgvLib.SingleOrder calldata order
    ) internal override {
      
      (uint old_wants, uint old_gives,,) = unpackOfferFromOrder(order);
      console.log(old_wants,old_gives);
      uint price_quote = oracle.getPrice(order.quote);
      uint price_base = oracle.getPrice(order.base);

      uint new_offer_wants = div_(
        mul_(old_wants, price_base),
        price_quote
      );
      console.log("Reposting offer at new price ", new_offer_wants, old_gives);
      // since offer is persistent it will auto refill if contract does not have enough provision on the Mangrove
      updateOffer(
        order.base, 
        order.quote, 
        new_offer_wants,
        old_gives, MAXUINT, MAXUINT, MAXUINT, 
        order.offerId
      );
  }
  function __autoRefill__(uint amount) internal override {
    require (address(this).balance >= amount, "Insufficient fund to provision offer");
    MGV.fund{value:amount}();
  }

  function __postHookFallback__(string memory message, MgvLib.SingleOrder calldata order) override internal {
    console.log(message);
  }
  
  // Closing diamond inheritance for solidity compiler
  // get/put and lender strat's functions
  function __get__(IERC20 base, uint amount) override(MangroveOffer, AaveLender) internal returns (uint){
    AaveLender.__get__(base, amount);
  }
  function __put__(IERC20 quote, uint amount) override(MangroveOffer, AaveLender)  internal {
    AaveLender.__put__(quote, amount);
  }

  // lastlook is defensive strat's function
  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override(MangroveOffer, Defensive)
  {
    Defensive.__lastLook__(order);
  }

}
