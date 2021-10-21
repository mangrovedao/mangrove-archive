pragma solidity ^0.7.0;
pragma abicoder v2;

import "../../Defensive.sol";
import "../../AaveLender.sol";

//import "hardhat/console.sol";

contract PriceFed is Defensive, AaveLender {
  constructor(
    address _oracle,
    address _addressesProvider,
    address payable _MGV
  ) Defensive(_oracle) AaveLender(_addressesProvider, 0) MangroveOffer(_MGV) {}

  event Slippage(uint indexed offerId, uint old_wants, uint new_wants);

  // reposts only if offer was reneged due to a price slippage
  function __posthookReneged__(MgvLib.SingleOrder calldata order)
    internal
    override
  {
    (uint old_wants, uint old_gives, , ) = unpackOfferFromOrder(order);
    uint price_quote = oracle.getPrice(order.inbound_tkn);
    uint price_base = oracle.getPrice(order.outbound_tkn);

    uint new_offer_wants = div_(mul_(old_gives, price_base), price_quote);
    emit Slippage(order.offerId, old_wants, new_offer_wants);
    // since offer is persistent it will auto refill if contract does not have enough provision on the Mangrove
    try
      this.updateOffer(
        order.outbound_tkn,
        order.inbound_tkn,
        new_offer_wants,
        old_gives,
        OFR_GASREQ,
        0,
        0,
        order.offerId
      )
    {} catch Error(string memory message) {
      emit PosthookFail(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        message
      );
    }
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