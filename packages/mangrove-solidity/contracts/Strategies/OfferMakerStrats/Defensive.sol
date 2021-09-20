pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "../interfaces/IOracle.sol";

// SPDX-License-Identifier: MIT

contract Defensive is MangroveOffer {

  uint16 slippage_num;
  uint16 constant slippage_den = 10**4; 
  IOracle oracle;

  constructor(
    address _oracle,
    address payable _MGV
  ) MangroveOffer(_MGV) {
    require(!(_oracle == address(0)), "Invalid oracle address");
    oracle = IOracle(_oracle);
  }

  function setSlippage(uint _slippage) external onlyAdmin {
    require(uint16(_slippage) == _slippage, "Slippage overflow");
    require(_slippage >= slippage_den, "Invalid slippage");
    slippage_num = uint16(_slippage);
  }

  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
  {
    uint oracle_gives =
      mul_( 
        order.wants,
        oracle.getPrice(order.base) // returns price in oracle base units (i.e ETH or USD)
      );
    uint oracle_wants =
      mul_(
        order.gives, 
        oracle.getPrice(order.quote) // returns price is oracle base units (i.e ETH or USD)
      );
    uint offer_wants = order.gives; //padded uint96
    uint offer_gives = order.wants; //padded uint96
    
    // if Oracle_price - slippage * Offer_price <= Offer_price we are happy
    // otherwise renege
    // i.e one verifies Offer_price - Oracle_price + slippage * Offer_price >= 0
    // with
    // Oracle_price := price(offer_gives)/price(offer_wants)
    // Offer_price := offer_gives/offer_wants
    // slippage := slippage_num / slippage_den
    // one gets (minimizing rounding errors), *accept* trade iff:
    // slippage_den[16] * offer_wants[96] * price(offer_gives)[96] + slippage_num[16] * offer_gives[96] * price(offer_wants)[96] >= offer_gives * prices(offer_wants)
    // which cannot overflow
    uint oracleWantsTimesOfferGives = mul_(oracle_wants, offer_gives); // both are padded uint96 cannot overflow
    uint offerWantsTimesOracleGives = mul_(offer_wants, oracle_gives); // both are padded uint96 cannot overflow
    if ( 
      add_(
        mul_(offerWantsTimesOracleGives, slippage_den),
        mul_(slippage_num, offerWantsTimesOracleGives)
      ) <
      mul_(oracleWantsTimesOfferGives, slippage_den)
    ) {

      //revert if price is beyond slippage
      returnData({
        drop: true,
        postHook_switch: PostHook.PriceUpdate,
        arg0: uint96(oracle_wants),
        arg1: uint96(oracle_gives)
      }); //passing fail data to __finalize__
    } else {
      // Slippage is not enough to drop trade, offer is consumed
      returnData({
        drop: false,
        postHook_switch: PostHook.Success
      });
    }
  }

}
