pragma solidity ^0.7.0;
pragma abicoder v2;

import "../Defensive.sol";
import "../AaveLender.sol";

//import "hardhat/console.sol";
import "../../lib/consolerr/consolerr.sol";

contract PriceFed is Defensive, AaveLender {
  constructor(
    address _oracle,
    address _addressesProvider,
    address payable _MGV
  ) Defensive(_oracle) AaveLender(_addressesProvider, 0) MangroveOffer(_MGV) {}

  event Slippage(uint indexed offerId, uint old_wants, uint new_wants);

  // reposts only if offer was reneged due to a price slippage
  function __postHookReneged__(
    bytes32 message,
    MgvLib.SingleOrder calldata order
  ) internal override {
    (uint old_wants, uint old_gives, , ) = unpackOfferFromOrder(order);
    uint price_quote = oracle.getPrice(order.inbound_tkn);
    uint price_base = oracle.getPrice(order.outbound_tkn);

    uint new_offer_wants = div_(mul_(old_gives, price_base), price_quote);
    emit Slippage(order.offerId, old_wants, new_offer_wants);
    // since offer is persistent it will auto refill if contract does not have enough provision on the Mangrove
    updateOfferInternal(
      order.outbound_tkn,
      order.inbound_tkn,
      new_offer_wants,
      old_gives,
      MAXUINT,
      MAXUINT,
      MAXUINT,
      order.offerId
    );
  }

  function __autoRefill__(uint amount) internal override {
    require(
      address(this).balance >= amount,
      "Insufficient fund to provision offer"
    );
    MGV.fund{value: amount}();
  }

  function __postHookFallback__(
    bytes32 message,
    MgvLib.SingleOrder calldata order
  ) internal override {
    consolerr.errorBytes32("Fallback posthook", message);
  }

  // Closing diamond inheritance for solidity compiler
  // get/put and lender strat's functions
  function __get__(IERC20 base, uint amount)
    internal
    override(MangroveOffer, AaveLender)
    returns (uint)
  {
    AaveLender.__get__(base, amount);
  }

  function __put__(IERC20 quote, uint amount)
    internal
    override(MangroveOffer, AaveLender)
  {
    AaveLender.__put__(quote, amount);
  }

  // lastlook is defensive strat's function
  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override(MangroveOffer, Defensive)
    returns (bool)
  {
    return Defensive.__lastLook__(order);
  }
}
