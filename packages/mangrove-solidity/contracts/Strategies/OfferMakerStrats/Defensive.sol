pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MangroveOffer.sol";
import "../interfaces/IOracle.sol";
import "hardhat/console.sol";

// SPDX-License-Identifier: MIT

abstract contract Defensive is MangroveOffer {

  uint16 slippage_num;
  uint16 constant slippage_den = 10**4; 
  IOracle public oracle;

  constructor(address _oracle) {
    require(!(_oracle == address(0)), "Invalid oracle address");
    oracle = IOracle(_oracle);
  }

  function setSlippage(uint _slippage) external onlyAdmin {
    require(uint16(_slippage) == _slippage, "Slippage overflow");
    require(_slippage >= slippage_den, "Slippage should be <= 1");
    slippage_num = uint16(_slippage);
  }

  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
  {
    uint offer_gives_REF =
      mul_( 
        order.wants,
        oracle.getPrice(order.base) // returns price in oracle base units (i.e ETH or USD)
      );
    uint offer_wants_REF =
      mul_(
        order.gives, 
        oracle.getPrice(order.quote) // returns price is oracle base units (i.e ETH or USD)
      );
    if (offer_gives_REF == 0 || offer_wants_REF == 0) {
      returnData({
        drop:true,
        postHook_switch: PostHook.Fallback,
        message: "Missing price data"
      });
    }    
    
    // if offer_gives_REF * (1-slippage) > offer_wants_REF one is getting arb'ed 
    if (
      sub_(
        mul_(offer_gives_REF, slippage_den),
        mul_(offer_gives_REF, slippage_num)
      ) > mul_(offer_wants_REF, slippage_den)
    ) {
      console.log("Reneging on trade!");
      //revert if price is beyond slippage
      returnData({
        drop: true,
        postHook_switch: PostHook.PriceUpdate
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
